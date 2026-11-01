import AVFoundation
import AppKit
import ImageIO

/// Temp files live in one folder. The app clears it on launch, quit and each new capture.
enum TempFiles {
  static let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("screenshot-gif", isDirectory: true)

  static func wipe() {
    try? FileManager.default.removeItem(at: root)
  }

  /// Clears old captures and returns a fresh folder.
  static func newCaptureFolder() -> URL {
    wipe()
    let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// A file name like "Capture 2026-11-01 at 01.23.45", so pastes don't share a name.
  static func baseName() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "Capture \(f.string(from: Date()))"
  }
}

enum Clipboard {
  static func copyFile(_ url: URL) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([url as NSURL])
  }
}

struct PDFResult {
  let url: URL
  let frames: Int
  let pages: Int
}

enum Exporter {
  /// Picks changed frames from the recording, pulls them from the MP4, and writes the PDF.
  static func makePDF(from recording: Recording, maxFrames: Int, to url: URL) async throws
    -> PDFResult
  {
    let picks = FrameSelector.select(
      recording.thumbs.map(\.luma), times: recording.thumbs.map(\.time.seconds),
      maxFrames: maxFrames)
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: recording.mp4))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    var frames: [SheetFrame] = []
    for index in picks {
      let time = recording.thumbs[index].time
      let (image, _) = try await generator.image(at: time)
      frames.append(SheetFrame(image: image, time: time.seconds))
    }
    let info = SheetInfo(
      duration: recording.duration, fps: recording.fps, capturedFrames: recording.thumbs.count)
    let pages = try SheetRenderer.render(
      frames: frames, pointSize: recording.pointSize,
      maxScale: recording.pixelSize.width / recording.pointSize.width, info: info, to: url)
    return PDFResult(url: url, frames: frames.count, pages: pages)
  }

  /// Dev check: builds a PDF from a GIF, treating the GIF as 1x.
  static func pdfFromGIF(input: URL, output: URL, maxFrames: Int) throws -> PDFResult {
    guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else {
      throw CocoaError(.fileReadCorruptFile)
    }
    var images: [CGImage] = []
    var times: [Double] = []
    var t = 0.0
    for i in 0..<CGImageSourceGetCount(source) {
      guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
      images.append(image)
      times.append(t)
      let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
      let gif = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
      t += (gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double) ?? 0.1
    }
    guard let first = images.first else { throw CocoaError(.fileReadCorruptFile) }
    let picks = FrameSelector.select(
      images.map(Thumbnailer.luma), times: times, maxFrames: maxFrames)
    let frames = picks.map { SheetFrame(image: images[$0], time: times[$0]) }
    let fps = Int((Double(images.count) / max(t, 0.001)).rounded())
    let pages = try SheetRenderer.render(
      frames: frames, pointSize: CGSize(width: first.width, height: first.height), maxScale: 1,
      info: SheetInfo(duration: t, fps: fps, capturedFrames: images.count), to: output)
    return PDFResult(url: output, frames: frames.count, pages: pages)
  }
}
