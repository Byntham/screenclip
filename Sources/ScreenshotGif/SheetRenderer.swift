import AppKit
import CoreText

struct SheetFrame {
  let image: CGImage
  let time: Double
}

struct SheetInfo {
  let duration: Double
  let fps: Int
  let capturedFrames: Int
}

/// Lays frames out in grids, one grid per PDF page, each frame labeled with its number and time.
enum SheetRenderer {
  /// Agents shrink images past roughly 1500 to 2500 px, so pages stay near this size.
  static let maxPage: CGFloat = 2000
  static let maxPerPage = 6
  static let pad: CGFloat = 10
  static let labelHeight: CGFloat = 30
  static let headerHeight: CGFloat = 40

  struct Layout {
    let cols: Int
    let rows: Int
    let scale: CGFloat
  }

  /// Picks the grid that fits the most frames per page with frames at 1x or larger.
  /// Among grids that fit the same number, picks the largest scale.
  static func layout(pointSize: CGSize, maxScale: CGFloat, frameCount: Int) -> Layout {
    var best = Layout(cols: 1, rows: 1, scale: 0)
    var bestUseful = 0
    for cols in 1...maxPerPage {
      for rows in 1...maxPerPage where cols * rows <= maxPerPage {
        let sw = (maxPage - pad * CGFloat(cols + 1)) / (CGFloat(cols) * pointSize.width)
        let sh = (maxPage - headerHeight - pad * CGFloat(rows + 1) - labelHeight * CGFloat(rows))
          / (CGFloat(rows) * pointSize.height)
        let scale = min(maxScale, sw, sh)
        guard scale >= 1 || (cols == 1 && rows == 1) else { continue }
        let useful = min(cols * rows, frameCount)
        let better =
          useful > bestUseful
          || (useful == bestUseful && scale > best.scale + 0.01)
          || (useful == bestUseful && abs(scale - best.scale) <= 0.01
            && cols * rows < best.cols * best.rows)
        if better {
          best = Layout(cols: cols, rows: rows, scale: scale)
          bestUseful = useful
        }
      }
    }
    return best
  }

  /// Writes the PDF and returns the page count.
  static func render(
    frames: [SheetFrame], pointSize: CGSize, maxScale: CGFloat, info: SheetInfo, to url: URL
  ) throws -> Int {
    let layout = layout(pointSize: pointSize, maxScale: maxScale, frameCount: frames.count)
    let fw = (pointSize.width * layout.scale).rounded()
    let fh = (pointSize.height * layout.scale).rounded()
    let perPage = layout.cols * layout.rows
    let pages = stride(from: 0, to: frames.count, by: perPage).map {
      Array(frames[$0..<min($0 + perPage, frames.count)])
    }

    guard let ctx = CGContext(url as CFURL, mediaBox: nil, nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    var number = 1
    for (p, page) in pages.enumerated() {
      let cols = pages.count > 1 ? layout.cols : min(layout.cols, page.count)
      let rows = (page.count + cols - 1) / cols
      let width = CGFloat(cols) * fw + pad * CGFloat(cols + 1)
      let height = headerHeight + CGFloat(rows) * (fh + labelHeight) + pad * CGFloat(rows + 1)
      var box = CGRect(x: 0, y: 0, width: width, height: height)
      ctx.beginPage(mediaBox: &box)
      ctx.setFillColor(CGColor(gray: 0.13, alpha: 1))
      ctx.fill(box)

      let last = number + page.count - 1
      let header =
        "Page \(p + 1)/\(pages.count) · frames \(number)–\(last) of \(frames.count)"
        + " · \(String(format: "%.1f", info.duration))s at \(info.fps) fps"
        + " · picked where the screen changed"
      drawText(
        header, in: ctx, at: CGPoint(x: pad, y: height - 27), maxWidth: width - pad * 2,
        size: 16, color: CGColor(gray: 0.75, alpha: 1), bold: false)

      for (n, frame) in page.enumerated() {
        let x = pad + CGFloat(n % cols) * (fw + pad)
        let top = height - headerHeight - pad - CGFloat(n / cols) * (fh + labelHeight + pad)
        drawText(
          "#\(number)  t=\(String(format: "%.2f", frame.time))s", in: ctx,
          at: CGPoint(x: x + 2, y: top - 22), maxWidth: fw - 4, size: 18,
          color: CGColor(red: 1, green: 0.85, blue: 0.3, alpha: 1), bold: true)
        let imageRect = CGRect(x: x, y: top - labelHeight - fh, width: fw, height: fh)
        ctx.draw(resized(frame.image, width: Int(fw), height: Int(fh)), in: imageRect)
        ctx.setStrokeColor(CGColor(gray: 0.35, alpha: 1))
        ctx.setLineWidth(1)
        ctx.stroke(imageRect.insetBy(dx: -0.5, dy: -0.5))
        number += 1
      }
      ctx.endPage()
    }
    ctx.closePDF()
    return pages.count
  }

  /// Draws one line of text, shrinking it to fit `maxWidth`.
  private static func drawText(
    _ text: String, in ctx: CGContext, at point: CGPoint, maxWidth: CGFloat, size: CGFloat,
    color: CGColor, bold: Bool
  ) {
    var fontSize = size
    var line: CTLine
    repeat {
      let font = CTFontCreateWithName((bold ? "Menlo-Bold" : "Menlo-Regular") as CFString, fontSize, nil)
      let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
      ]
      line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
      if CTLineGetTypographicBounds(line, nil, nil, nil) <= maxWidth || fontSize <= 8 { break }
      fontSize -= 1
    } while true
    ctx.textPosition = point
    CTLineDraw(line, ctx)
  }

  /// Resamples so the PDF stores the image at its drawn size, not full capture size.
  private static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage {
    if image.width == width && image.height == height { return image }
    guard
      let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return image }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage() ?? image
  }
}
