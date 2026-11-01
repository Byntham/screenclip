import Accelerate
import CoreGraphics
import CoreVideo

/// Shrinks frames to small grayscale images for change detection.
enum Thumbnailer {
  static let width = 192

  static func size(_ w: Int, _ h: Int) -> (Int, Int) {
    let tw = min(width, w)
    return (tw, max(1, h * tw / w))
  }

  static func luma(_ pixelBuffer: CVPixelBuffer) -> [UInt8] {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    let w = CVPixelBufferGetWidth(pixelBuffer)
    let h = CVPixelBufferGetHeight(pixelBuffer)
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
    let (tw, th) = size(w, h)
    var src = vImage_Buffer(
      data: base, height: vImagePixelCount(h), width: vImagePixelCount(w),
      rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer))
    var bgra = [UInt8](repeating: 0, count: tw * th * 4)
    bgra.withUnsafeMutableBytes { buf in
      var dst = vImage_Buffer(
        data: buf.baseAddress, height: vImagePixelCount(th), width: vImagePixelCount(tw),
        rowBytes: tw * 4)
      _ = vImageScale_ARGB8888(&src, &dst, nil, vImage_Flags(kvImageNoFlags))
    }
    return toLuma(bgra)
  }

  static func luma(_ image: CGImage) -> [UInt8] {
    let (tw, th) = size(image.width, image.height)
    var bgra = [UInt8](repeating: 0, count: tw * th * 4)
    bgra.withUnsafeMutableBytes { buf in
      let ctx = CGContext(
        data: buf.baseAddress, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: tw * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue)!
      ctx.interpolationQuality = .medium
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
    }
    return toLuma(bgra)
  }

  /// BGRA bytes to 8-bit luma.
  private static func toLuma(_ bgra: [UInt8]) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: bgra.count / 4)
    for i in 0..<out.count {
      let b = Int(bgra[i * 4]), g = Int(bgra[i * 4 + 1]), r = Int(bgra[i * 4 + 2])
      out[i] = UInt8((r * 77 + g * 150 + b * 29) >> 8)
    }
    return out
  }
}

/// Picks the frames worth showing.
///
/// If few frames changed, it keeps every changed frame. Otherwise it spreads the budget along
/// the timeline by how much changed, with some weight for elapsed time. Busy stretches get more
/// frames, and a long pause still gets one.
enum FrameSelector {
  /// How much a thumbnail pixel must change to count as changed.
  static let pixelDelta = 16
  /// Share of the budget spread by time instead of by change.
  static let timeWeight = 0.3

  static func changedPixels(_ a: [UInt8], _ b: [UInt8]) -> Int {
    guard a.count == b.count else { return a.count }
    var n = 0
    a.withUnsafeBufferPointer { pa in
      b.withUnsafeBufferPointer { pb in
        for i in 0..<pa.count {
          let d = Int(pa[i]) - Int(pb[i])
          if d > pixelDelta || d < -pixelDelta { n += 1 }
        }
      }
    }
    return n
  }

  /// Returns indices of picked frames, in order, at most `maxFrames`.
  /// Always includes the first frame.
  static func select(_ thumbs: [[UInt8]], times: [Double], maxFrames: Int) -> [Int] {
    guard let first = thumbs.first else { return [] }
    guard thumbs.count > 1, maxFrames > 1 else { return [0] }
    // A few changed thumbnail pixels: about one small UI element.
    let base = max(4, first.count / 4000)

    // Every frame that differs from the last kept one.
    var changed = [0]
    var last = first
    for i in 1..<thumbs.count where changedPixels(thumbs[i], last) >= base {
      changed.append(i)
      last = thumbs[i]
    }
    if changed.count <= maxFrames { return changed }

    // Cumulative weight along the timeline, from 0 to 1.
    var change = [Double](repeating: 0, count: thumbs.count)
    for i in 1..<thumbs.count {
      let n = changedPixels(thumbs[i], thumbs[i - 1])
      change[i] = n >= base ? Double(n) : 0
    }
    let totalChange = change.reduce(0, +)
    let duration = max(times.last! - times.first!, 0.001)
    var cumulative = [Double](repeating: 0, count: thumbs.count)
    for i in 1..<thumbs.count {
      let byChange = totalChange > 0 ? change[i] / totalChange : 0
      let byTime = (times[i] - times[i - 1]) / duration
      let w = totalChange > 0 ? (1 - timeWeight) * byChange + timeWeight * byTime : byTime
      cumulative[i] = cumulative[i - 1] + w
    }

    // Evenly spaced targets. One big jump can swallow several targets, so search for the
    // target count that gives the most distinct frames within the budget.
    func picks(_ targets: Int) -> [Int] {
      var out: [Int] = []
      var i = 0
      for k in 0..<targets {
        let target = Double(k) / Double(targets - 1) * cumulative.last! - 1e-9
        while i < cumulative.count - 1 && cumulative[i] < target { i += 1 }
        if out.last != i { out.append(i) }
      }
      return out
    }
    var lo = 2
    var hi = thumbs.count
    while lo < hi {
      let mid = (lo + hi + 1) / 2
      if picks(mid).count <= maxFrames { lo = mid } else { hi = mid - 1 }
    }
    return picks(lo)
  }
}
