import AppKit

/// The border around the recording area and the 3, 2, 1 countdown.
/// The border sits just outside the area, and the recorder excludes this app's windows anyway.
@MainActor
final class RegionChrome {
  static let margin: CGFloat = 6
  private let window: NSWindow
  private let view: ChromeView

  init(rect: CGRect) {
    let frame = rect.insetBy(dx: -RegionChrome.margin, dy: -RegionChrome.margin)
    window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.setFrame(frame, display: false)
    window.level = .screenSaver
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.isReleasedWhenClosed = false
    window.sharingType = .none
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    view = ChromeView(frame: CGRect(origin: .zero, size: frame.size))
    window.contentView = view
    window.orderFrontRegardless()
  }

  func showCountdown(_ number: Int?) {
    view.countdown = number
    view.needsDisplay = true
  }

  func setRecording() {
    view.recording = true
    view.needsDisplay = true
  }

  func close() { window.orderOut(nil) }
}

private final class ChromeView: NSView {
  var countdown: Int?
  var recording = false

  override func draw(_ dirtyRect: NSRect) {
    let border = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
    border.lineWidth = 2
    if recording {
      NSColor.systemRed.setStroke()
    } else {
      NSColor.white.setStroke()
      border.setLineDash([6, 4], count: 2, phase: 0)
    }
    border.stroke()

    guard let countdown else { return }
    let text = "\(countdown)" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 56, weight: .bold),
      .foregroundColor: NSColor.white,
    ]
    let size = text.size(withAttributes: attrs)
    let side = max(size.width, size.height) + 28
    let box = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    NSColor.black.withAlphaComponent(0.6).setFill()
    NSBezierPath(roundedRect: box, xRadius: 16, yRadius: 16).fill()
    text.draw(
      at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2),
      withAttributes: attrs)
  }
}

/// A small message under the capture area, such as "Copied PDF".
@MainActor
enum HUD {
  private static var window: NSWindow?
  private static var hideWork: DispatchWorkItem?

  static func show(_ message: String, near rect: CGRect?, hideAfter seconds: Double? = nil) {
    hideWork?.cancel()
    window?.orderOut(nil)

    let label = NSTextField(labelWithString: message)
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.textColor = .white
    label.sizeToFit()
    let size = CGSize(width: label.frame.width + 28, height: label.frame.height + 16)

    let screen = rect.flatMap { r in NSScreen.screens.first { $0.frame.intersects(r) } }
      ?? NSScreen.main
    let visible = screen?.visibleFrame ?? .zero
    let anchor = rect ?? visible
    var origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 14)
    if origin.y < visible.minY + 8 { origin.y = anchor.minY + 14 }
    origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)

    let w = NSWindow(
      contentRect: CGRect(origin: origin, size: size), styleMask: .borderless,
      backing: .buffered, defer: false)
    w.level = .screenSaver
    w.isOpaque = false
    w.backgroundColor = .clear
    w.ignoresMouseEvents = true
    w.isReleasedWhenClosed = false
    w.sharingType = .none
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

    let bg = NSView(frame: CGRect(origin: .zero, size: size))
    bg.wantsLayer = true
    bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
    bg.layer?.cornerRadius = 10
    label.frame.origin = CGPoint(x: 14, y: 8)
    bg.addSubview(label)
    w.contentView = bg
    w.orderFrontRegardless()
    window = w

    if let seconds {
      let work = DispatchWorkItem { hide() }
      hideWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
  }

  static func hide() {
    hideWork?.cancel()
    window?.orderOut(nil)
    window = nil
  }
}
