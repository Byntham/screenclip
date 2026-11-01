import AppKit
import Carbon.HIToolbox
import Combine

/// A global hotkey: a virtual key code plus Carbon modifier flags.
struct KeyCombo: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var key: String

  static let `default` = KeyCombo(
    keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(cmdKey | shiftKey), key: "Z")

  init(keyCode: UInt32, modifiers: UInt32, key: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.key = key
  }

  /// Builds a combo from a key press. Needs at least one of ⌘, ⌃ or ⌥.
  init?(event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    var m: UInt32 = 0
    if flags.contains(.command) { m |= UInt32(cmdKey) }
    if flags.contains(.shift) { m |= UInt32(shiftKey) }
    if flags.contains(.option) { m |= UInt32(optionKey) }
    if flags.contains(.control) { m |= UInt32(controlKey) }
    guard m & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
    keyCode = UInt32(event.keyCode)
    modifiers = m
    key = KeyCombo.name(for: event)
  }

  var display: String {
    var s = ""
    if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
    return s + key
  }

  private static let specialKeys: [Int: String] = [
    kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
    kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
    kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
    kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
    kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
    kVK_F11: "F11", kVK_F12: "F12",
  ]

  private static func name(for event: NSEvent) -> String {
    if let special = specialKeys[Int(event.keyCode)] { return special }
    let chars = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? "?"
    return chars.uppercased()
  }
}

enum OutputFormat: String, CaseIterable, Identifiable {
  case pdf, mp4
  var id: String { rawValue }
}

/// User settings, saved in UserDefaults.
@MainActor
final class Settings: ObservableObject {
  static let shared = Settings()
  static let fpsChoices = [10, 15, 30, 60]
  static let maxSecondsChoices = [10, 15, 30, 60, 120]
  static let maxFramesChoices = [12, 24, 36, 48, 72]

  private let defaults = UserDefaults.standard

  @Published var hotkey: KeyCombo {
    didSet {
      if let data = try? JSONEncoder().encode(hotkey) { defaults.set(data, forKey: "hotkey") }
    }
  }
  @Published var fps: Int { didSet { defaults.set(fps, forKey: "fps") } }
  @Published var maxSeconds: Int { didSet { defaults.set(maxSeconds, forKey: "maxSeconds") } }
  @Published var maxFrames: Int { didSet { defaults.set(maxFrames, forKey: "maxFrames") } }
  @Published var output: OutputFormat { didSet { defaults.set(output.rawValue, forKey: "output") } }
  @Published var showCursor: Bool { didSet { defaults.set(showCursor, forKey: "showCursor") } }

  /// True while the settings window is waiting for a new hotkey.
  @Published var isRecordingHotkey = false
  /// Set when the hotkey can't be registered, for example because another app owns it.
  @Published var hotkeyError: String?

  private init() {
    if let data = defaults.data(forKey: "hotkey"),
      let combo = try? JSONDecoder().decode(KeyCombo.self, from: data)
    {
      hotkey = combo
    } else {
      hotkey = .default
    }
    fps = defaults.object(forKey: "fps") as? Int ?? 15
    maxSeconds = defaults.object(forKey: "maxSeconds") as? Int ?? 30
    maxFrames = defaults.object(forKey: "maxFrames") as? Int ?? 48
    output = OutputFormat(rawValue: defaults.string(forKey: "output") ?? "") ?? .pdf
    showCursor = defaults.object(forKey: "showCursor") as? Bool ?? true
  }
}
