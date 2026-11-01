import AppKit

/// An area chosen by the user. `rect` is in global AppKit coordinates (points, origin bottom left).
struct Selection {
  let screen: NSScreen
  let rect: CGRect
}

/// Shows a dimmed overlay on every screen and lets the user drag out an area, like ⇧⌘4.
/// Esc cancels. The drag stays on the screen where it started.
@MainActor
final class SelectionController {
  private var windows: [SelectionWindow] = []
  private var completion: ((Selection?) -> Void)?
  private var previousApp: NSRunningApplication?
  private var start: CGPoint?
  private var current: CGPoint?
  private var startScreen: NSScreen?

  var selectionRect: CGRect? {
    guard let start, let current else { return nil }
    return CGRect(
      x: min(start.x, current.x), y: min(start.y, current.y),
      width: abs(start.x - current.x), height: abs(start.y - current.y))
  }

  func begin(completion: @escaping (Selection?) -> Void) {
    self.completion = completion
    previousApp = NSWorkspace.shared.frontmostApplication
    for screen in NSScreen.screens {
      let window = SelectionWindow(screen: screen, controller: self)
      windows.append(window)
      window.orderFrontRegardless()
    }
    NSApp.activate()
    let mouse = NSEvent.mouseLocation
    let keyWindow = windows.first { $0.frame.contains(mouse) } ?? windows.first
    keyWindow?.makeKeyAndOrderFront(nil)
    NSCursor.crosshair.push()
  }

  fileprivate func mouseDown() {
    let p = NSEvent.mouseLocation
    startScreen = NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
    start = p
    current = p
    redraw()
  }

  fileprivate func mouseDragged() {
    guard let frame = startScreen?.frame else { return }
    var p = NSEvent.mouseLocation
    p.x = min(max(p.x, frame.minX), frame.maxX)
    p.y = min(max(p.y, frame.minY), frame.maxY)
    current = p
    redraw()
  }

  fileprivate func mouseUp() {
    guard let screen = startScreen, let raw = selectionRect else { return finish(nil) }
    let rect = raw.integral.intersection(screen.frame)
    guard rect.width >= 8, rect.height >= 8 else { return finish(nil) }
    finish(Selection(screen: screen, rect: rect))
  }

  fileprivate func cancel() { finish(nil) }

  private func finish(_ selection: Selection?) {
    NSCursor.pop()
    windows.forEach { $0.orderOut(nil) }
    windows = []
    // Give focus back so the user can work in their app while recording.
    previousApp?.activate()
    let done = completion
    completion = nil
    done?(selection)
  }

  private func redraw() {
    windows.forEach { $0.contentView?.needsDisplay = true }
  }
}

private final class SelectionWindow: NSWindow {
  init(screen: NSScreen, controller: SelectionController) {
    super.init(
      contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    setFrame(screen.frame, display: false)
    level = .screenSaver
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    let view = SelectionView(controller: controller)
    contentView = view
    initialFirstResponder = view
  }

  override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
  private weak var controller: SelectionController?

  init(controller: SelectionController) {
    self.controller = controller
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) { fatalError() }

  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

  override func mouseDown(with event: NSEvent) { controller?.mouseDown() }
  override func mouseDragged(with event: NSEvent) { controller?.mouseDragged() }
  override func mouseUp(with event: NSEvent) { controller?.mouseUp() }
  override func cancelOperation(_ sender: Any?) { controller?.cancel() }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { controller?.cancel() }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.black.withAlphaComponent(0.25).setFill()
    bounds.fill()
    guard let window, let rect = controller?.selectionRect, rect.width > 0, rect.height > 0
    else { return }
    let local = rect.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
    NSColor.clear.setFill()
    local.fill(using: .copy)
    NSColor.white.setStroke()
    let border = NSBezierPath(rect: local.insetBy(dx: -0.5, dy: -0.5))
    border.lineWidth = 1
    border.stroke()

    let text = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
      .foregroundColor: NSColor.white,
    ]
    let size = text.size(withAttributes: attrs)
    var origin = CGPoint(x: local.maxX - size.width - 8, y: local.minY - size.height - 10)
    if origin.y < 4 { origin.y = local.minY + 6 }
    let pill = CGRect(
      x: origin.x - 6, y: origin.y - 3, width: size.width + 12, height: size.height + 6)
    NSColor.black.withAlphaComponent(0.7).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
    text.draw(at: origin, withAttributes: attrs)
  }
}
