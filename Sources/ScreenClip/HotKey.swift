import Carbon.HIToolbox

/// A system-wide hotkey through Carbon's RegisterEventHotKey.
/// It needs no Accessibility permission. The key press goes only to this app.
final class HotKey {
  private static var handlers: [UInt32: () -> Void] = [:]
  private static var nextID: UInt32 = 1
  private static var installed = false
  private static let signature: OSType = 0x5343_4C50  // "SCLP"

  private var ref: EventHotKeyRef?
  private let id: UInt32

  /// Returns nil if the key combination is already taken.
  init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
    HotKey.installHandlerIfNeeded()
    id = HotKey.nextID
    HotKey.nextID += 1
    let hotKeyID = EventHotKeyID(signature: HotKey.signature, id: id)
    let status = RegisterEventHotKey(
      keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    guard status == noErr else { return nil }
    HotKey.handlers[id] = handler
  }

  deinit {
    if let ref { UnregisterEventHotKey(ref) }
    HotKey.handlers[id] = nil
  }

  private static func installHandlerIfNeeded() {
    guard !installed else { return }
    installed = true
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ in
        var hotKeyID = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
          nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        if hotKeyID.signature == HotKey.signature, let handler = HotKey.handlers[hotKeyID.id] {
          DispatchQueue.main.async { handler() }
        }
        return noErr
      }, 1, &spec, nil, nil)
  }
}
