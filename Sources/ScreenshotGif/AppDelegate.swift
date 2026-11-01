import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private enum Phase { case idle, selecting, countdown, starting, recording, processing }

  private let settings = Settings.shared
  private var phase = Phase.idle
  private var statusItem: NSStatusItem!
  private var hotkey: HotKey?
  private var escKey: HotKey?
  private var cancellables = Set<AnyCancellable>()

  private var selector: SelectionController?
  private var selection: Selection?
  private var chrome: RegionChrome?
  private var recorder: Recorder?
  private var countdownTimer: Timer?
  private var tickTimer: Timer?
  private var recordStart: Date?
  /// Bumped on every cancel, so finished async work from a cancelled capture is dropped.
  private var generation = 0

  private var lastRecording: Recording?
  private var lastPDF: PDFResult?
  private var settingsWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    TempFiles.wipe()
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu
    updateStatusItem()

    registerHotkey(settings.hotkey)
    settings.$hotkey.dropFirst().sink { [weak self] combo in
      self?.registerHotkey(combo)
    }.store(in: &cancellables)
    settings.$isRecordingHotkey.dropFirst().sink { [weak self] recording in
      guard let self else { return }
      if recording { self.hotkey = nil } else { self.registerHotkey(self.settings.hotkey) }
    }.store(in: &cancellables)

    if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
  }

  func applicationWillTerminate(_ notification: Notification) {
    TempFiles.wipe()
  }

  // MARK: Hotkeys

  private func registerHotkey(_ combo: KeyCombo) {
    hotkey = nil
    hotkey = HotKey(keyCode: combo.keyCode, modifiers: combo.modifiers) { [weak self] in
      self?.hotkeyPressed()
    }
    settings.hotkeyError =
      hotkey == nil ? "\(combo.display) is already taken by another app." : nil
  }

  /// Esc is grabbed system-wide only while a capture is in progress.
  private func setEscEnabled(_ enabled: Bool) {
    if enabled, escKey == nil {
      escKey = HotKey(keyCode: 53, modifiers: 0) { [weak self] in self?.cancelCapture() }
    } else if !enabled {
      escKey = nil
    }
  }

  private func hotkeyPressed() {
    switch phase {
    case .idle: beginSelection()
    case .recording: stopAndCopy()
    default: break
    }
  }

  // MARK: Capture flow

  private func beginSelection() {
    guard phase == .idle else { return }
    guard CGPreflightScreenCaptureAccess() else {
      CGRequestScreenCaptureAccess()
      showError(
        "Screen Recording permission is needed. Turn it on for Screenshot GIF in "
          + "System Settings > Privacy & Security > Screen & System Audio Recording, then try again.")
      return
    }
    HUD.hide()
    phase = .selecting
    let controller = SelectionController()
    selector = controller
    controller.begin { [weak self] selection in
      guard let self else { return }
      self.selector = nil
      if let selection { self.startCountdown(selection) } else { self.phase = .idle }
    }
  }

  private func startCountdown(_ selection: Selection) {
    self.selection = selection
    phase = .countdown
    setEscEnabled(true)
    chrome = RegionChrome(rect: selection.rect)
    var remaining = 3
    chrome?.showCountdown(remaining)
    countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
      MainActor.assumeIsolated {
        remaining -= 1
        if remaining > 0 {
          self?.chrome?.showCountdown(remaining)
        } else {
          timer.invalidate()
          self?.startRecording()
        }
      }
    }
  }

  private func startRecording() {
    guard phase == .countdown, let selection else { return }
    countdownTimer = nil
    chrome?.showCountdown(nil)
    chrome?.setRecording()
    lastRecording = nil
    lastPDF = nil
    let folder = TempFiles.newCaptureFolder()
    let url = folder.appendingPathComponent(TempFiles.baseName() + ".mp4")
    let recorder = Recorder(
      selection: selection, fps: settings.fps, showCursor: settings.showCursor, url: url)
    recorder.onError = { [weak self] error in self?.fail(error) }
    self.recorder = recorder
    phase = .starting
    let gen = generation
    Task {
      do {
        try await recorder.start()
        guard gen == self.generation else { return }
        self.phase = .recording
        self.recordStart = Date()
        self.startTicks()
      } catch {
        if gen == self.generation { self.fail(error) }
      }
    }
  }

  private func startTicks() {
    updateStatusItem()
    tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, let start = self.recordStart else { return }
        self.updateStatusItem()
        if Date().timeIntervalSince(start) >= Double(self.settings.maxSeconds) {
          self.stopAndCopy()
        }
      }
    }
  }

  private func stopAndCopy() {
    guard phase == .recording, let recorder else { return }
    phase = .processing
    tickTimer?.invalidate()
    tickTimer = nil
    recordStart = nil
    chrome?.close()
    chrome = nil
    updateStatusItem()
    HUD.show("Processing…", near: selection?.rect)
    let gen = generation
    let format = settings.output
    let maxFrames = settings.maxFrames
    Task {
      do {
        let recording = try await recorder.stop()
        guard gen == self.generation else { return }
        self.recorder = nil
        self.lastRecording = recording
        let message = try await self.copy(recording, as: format, maxFrames: maxFrames)
        guard gen == self.generation else { return }
        HUD.show(message, near: self.selection?.rect, hideAfter: 2)
        self.finishCapture()
      } catch {
        if gen == self.generation { self.fail(error) }
      }
    }
  }

  /// Esc at any point: nothing is copied and temp files are deleted.
  private func cancelCapture() {
    guard phase != .idle else { return }
    generation += 1
    countdownTimer?.invalidate()
    countdownTimer = nil
    if let recorder {
      self.recorder = nil
      Task { await recorder.cancel() }
    }
    lastRecording = nil
    lastPDF = nil
    TempFiles.wipe()
    HUD.hide()
    finishCapture()
  }

  private func finishCapture() {
    tickTimer?.invalidate()
    tickTimer = nil
    recordStart = nil
    chrome?.close()
    chrome = nil
    setEscEnabled(false)
    phase = .idle
    updateStatusItem()
  }

  private func fail(_ error: Error) {
    cancelCapture()
    showError(error.localizedDescription)
  }

  // MARK: Output

  private func copy(_ recording: Recording, as format: OutputFormat, maxFrames: Int) async throws
    -> String
  {
    switch format {
    case .mp4:
      Clipboard.copyFile(recording.mp4)
      return "Copied MP4 · \(String(format: "%.1f", recording.duration))s"
    case .pdf:
      let pdf = try await pdf(for: recording, maxFrames: maxFrames)
      Clipboard.copyFile(pdf.url)
      let pages = pdf.pages == 1 ? "1 page" : "\(pdf.pages) pages"
      return "Copied PDF · \(pdf.frames) frames on \(pages)"
    }
  }

  private func pdf(for recording: Recording, maxFrames: Int) async throws -> PDFResult {
    if let lastPDF { return lastPDF }
    let url = recording.mp4.deletingPathExtension().appendingPathExtension("pdf")
    let result = try await Exporter.makePDF(from: recording, maxFrames: maxFrames, to: url)
    lastPDF = result
    return result
  }

  @objc private func copyLastAsPDF() { copyLast(as: .pdf) }
  @objc private func copyLastAsMP4() { copyLast(as: .mp4) }

  private func copyLast(as format: OutputFormat) {
    guard phase == .idle, let recording = lastRecording else { return }
    phase = .processing
    let maxFrames = settings.maxFrames
    Task {
      do {
        let message = try await copy(recording, as: format, maxFrames: maxFrames)
        HUD.show(message, near: nil, hideAfter: 2)
      } catch {
        showError(error.localizedDescription)
      }
      phase = .idle
    }
  }

  // MARK: Menu bar

  private func updateStatusItem() {
    guard let button = statusItem.button else { return }
    let recording = phase == .recording
    let image = NSImage(
      systemSymbolName: recording ? "record.circle.fill" : "record.circle",
      accessibilityDescription: "Screenshot GIF")
    image?.isTemplate = true
    button.image = image
    button.contentTintColor = recording ? .systemRed : nil
    if recording, let start = recordStart {
      let s = Int(Date().timeIntervalSince(start))
      button.title = String(format: " %d:%02d", s / 60, s % 60)
    } else {
      button.title = ""
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    switch phase {
    case .recording:
      menu.addItem(item("Stop and Copy  \(settings.hotkey.display)", #selector(menuStop)))
      menu.addItem(item("Cancel  ⎋", #selector(menuCancel)))
    case .countdown, .starting, .selecting, .processing:
      menu.addItem(item("Cancel  ⎋", #selector(menuCancel)))
    case .idle:
      menu.addItem(item("Record Area  \(settings.hotkey.display)", #selector(menuRecord)))
    }
    menu.addItem(.separator())
    let canCopy = phase == .idle && lastRecording != nil
    let pdfItem = item("Copy Last Capture as PDF", #selector(copyLastAsPDF))
    pdfItem.isEnabled = canCopy
    let mp4Item = item("Copy Last Capture as MP4", #selector(copyLastAsMP4))
    mp4Item.isEnabled = canCopy
    menu.addItem(pdfItem)
    menu.addItem(mp4Item)
    menu.addItem(.separator())
    menu.addItem(item("Settings…", #selector(openSettings)))
    menu.addItem(item("Quit Screenshot GIF", #selector(quit)))
  }

  private func item(_ title: String, _ action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  @objc private func menuRecord() {
    // Let the menu close before the overlay takes the screen.
    DispatchQueue.main.async { self.beginSelection() }
  }
  @objc private func menuStop() { stopAndCopy() }
  @objc private func menuCancel() { cancelCapture() }
  @objc private func quit() { NSApp.terminate(nil) }

  @objc private func openSettings() {
    if settingsWindow == nil {
      let window = NSWindow(
        contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
      window.title = "Screenshot GIF Settings"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      settingsWindow = window
    }
    settingsWindow?.center()
    NSApp.activate()
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  private func showError(_ message: String) {
    HUD.hide()
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = "Screenshot GIF"
    alert.informativeText = message
    alert.runModal()
  }
}
