import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @ObservedObject var settings: Settings
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var loginError: String?

  var body: some View {
    Form {
      LabeledContent("Hotkey") {
        VStack(alignment: .trailing, spacing: 4) {
          HotkeyRecorder(settings: settings)
          if let error = settings.hotkeyError {
            Text(error).font(.caption).foregroundStyle(.red)
          }
        }
      }
      Picker("Frame rate", selection: $settings.fps) {
        ForEach(Settings.fpsChoices, id: \.self) { Text("\($0) fps").tag($0) }
      }
      Picker("Max length", selection: $settings.maxSeconds) {
        ForEach(Settings.maxSecondsChoices, id: \.self) { Text("\($0) seconds").tag($0) }
      }
      Picker("Copy as", selection: $settings.output) {
        Text("PDF frame sheet").tag(OutputFormat.pdf)
        Text("MP4 video").tag(OutputFormat.mp4)
      }
      Picker("Max frames in PDF", selection: $settings.maxFrames) {
        ForEach(Settings.maxFramesChoices, id: \.self) { Text("\($0)").tag($0) }
      }
      Toggle("Show cursor", isOn: $settings.showCursor)
      Toggle("Launch at login", isOn: launchBinding)
      if let loginError {
        Text(loginError).font(.caption).foregroundStyle(.red)
      }
    }
    .formStyle(.grouped)
    .frame(width: 420)
    .fixedSize()
  }

  private var launchBinding: Binding<Bool> {
    Binding(
      get: { launchAtLogin },
      set: { enabled in
        do {
          if enabled {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
          launchAtLogin = enabled
          loginError = nil
        } catch {
          loginError = error.localizedDescription
        }
      })
  }
}

/// Click, then press the new key combination. Esc stops without changing it.
private struct HotkeyRecorder: View {
  @ObservedObject var settings: Settings
  @State private var monitor: Any?

  var body: some View {
    Button(settings.isRecordingHotkey ? "Type new keys…" : settings.hotkey.display) {
      if settings.isRecordingHotkey { stop() } else { start() }
    }
    .onDisappear { stop() }
  }

  private func start() {
    settings.isRecordingHotkey = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == 53 {
        stop()
      } else if let combo = KeyCombo(event: event) {
        settings.hotkey = combo
        stop()
      }
      return nil
    }
  }

  private func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    if settings.isRecordingHotkey { settings.isRecordingHotkey = false }
  }
}
