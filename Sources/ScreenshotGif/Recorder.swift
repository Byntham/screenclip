import AVFoundation
import AppKit
import ScreenCaptureKit

/// A small grayscale copy of one captured frame, used to find frames where the screen changed.
struct Thumb {
  /// Time from the start of the MP4.
  let time: CMTime
  let luma: [UInt8]
}

struct Recording {
  let mp4: URL
  let thumbs: [Thumb]
  let duration: Double
  /// Size of the capture area in points.
  let pointSize: CGSize
  /// Size of the MP4 frames in pixels.
  let pixelSize: CGSize
  let fps: Int
}

enum RecorderError: LocalizedError {
  case noDisplay
  case noFrames
  case writer(String)

  var errorDescription: String? {
    switch self {
    case .noDisplay: "Couldn't find the display for that area."
    case .noFrames: "No frames were captured."
    case .writer(let message): "Couldn't write the video: \(message)"
    }
  }
}

/// Records one area of one display to an MP4 with ScreenCaptureKit,
/// and keeps a grayscale thumbnail of every frame.
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
  // H.264 hardware encoders top out around 4096 x 2304.
  private static let maxLongEdge: CGFloat = 4096
  private static let maxPixels: CGFloat = 4096 * 2304

  let url: URL
  private let selection: Selection
  private let fps: Int
  private let showCursor: Bool
  private let queue = DispatchQueue(label: "screenshot-gif.recorder")

  private var stream: SCStream?
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var firstPTS: CMTime?
  private var lastPTS: CMTime = .zero
  private var thumbs: [Thumb] = []
  private var pixelSize: CGSize = .zero
  private var cancelled = false

  /// Called on the main queue if capture stops on its own, for example when permission is revoked.
  var onError: ((Error) -> Void)?

  init(selection: Selection, fps: Int, showCursor: Bool, url: URL) {
    self.selection = selection
    self.fps = fps
    self.showCursor = showCursor
    self.url = url
  }

  func start() async throws {
    let screen = selection.screen
    let rect = selection.rect
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    guard let displayID = screen.deviceDescription[key] as? CGDirectDisplayID else {
      throw RecorderError.noDisplay
    }
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
      throw RecorderError.noDisplay
    }
    // Leave out this app's own windows: the border, countdown and HUD.
    let mine = content.applications.filter {
      $0.processID == ProcessInfo.processInfo.processIdentifier
    }
    let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])

    // ScreenCaptureKit wants the area relative to the display, origin top left.
    let frame = screen.frame
    let local = CGRect(
      x: rect.minX - frame.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)

    var pw = rect.width * screen.backingScaleFactor
    var ph = rect.height * screen.backingScaleFactor
    let fit = min(1, Recorder.maxLongEdge / max(pw, ph), (Recorder.maxPixels / (pw * ph)).squareRoot())
    pw = max(2, (pw * fit / 2).rounded(.down) * 2)
    ph = max(2, (ph * fit / 2).rounded(.down) * 2)
    pixelSize = CGSize(width: pw, height: ph)

    let config = SCStreamConfiguration()
    config.sourceRect = local
    config.width = Int(pw)
    config.height = Int(ph)
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
    config.showsCursor = showCursor
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.colorSpaceName = CGColorSpace.sRGB
    config.queueDepth = 8

    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let bitrate = min(60_000_000, max(8_000_000, Int(pw * ph) * fps / 4))
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(pw),
        AVVideoHeightKey: Int(ph),
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: bitrate,
          AVVideoMaxKeyFrameIntervalDurationKey: 1,
          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
          AVVideoExpectedSourceFrameRateKey: fps,
        ],
      ])
    input.expectsMediaDataInRealTime = true
    writer.add(input)
    guard writer.startWriting() else {
      throw RecorderError.writer(writer.error?.localizedDescription ?? "unknown error")
    }
    queue.sync {
      self.writer = writer
      self.input = input
    }

    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    try await stream.startCapture()
    self.stream = stream
    if queue.sync(execute: { cancelled }) { await cancel() }
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen, sampleBuffer.isValid, !cancelled,
      let writer, let input,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
      let rawStatus = attachments.first?[.status] as? Int,
      SCFrameStatus(rawValue: rawStatus) == .complete,
      let pixelBuffer = sampleBuffer.imageBuffer
    else { return }

    let pts = sampleBuffer.presentationTimeStamp
    if firstPTS == nil {
      writer.startSession(atSourceTime: pts)
      firstPTS = pts
    }
    guard input.isReadyForMoreMediaData, input.append(sampleBuffer), let firstPTS else { return }
    thumbs.append(Thumb(time: pts - firstPTS, luma: Thumbnailer.luma(pixelBuffer)))
    lastPTS = pts
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    DispatchQueue.main.async { self.onError?(error) }
  }

  /// Stops capture and finishes the MP4.
  func stop() async throws -> Recording {
    if let stream { try? await stream.stopCapture() }
    stream = nil
    // ScreenCaptureKit timestamps use the host clock.
    let end = CMClockGetTime(CMClockGetHostTimeClock())
    let (writer, input, firstPTS, lastPTS, thumbs) = queue.sync {
      (self.writer, self.input, self.firstPTS, self.lastPTS, self.thumbs)
    }
    guard let writer, let input else { throw RecorderError.writer("not started") }
    guard let firstPTS, !thumbs.isEmpty else {
      writer.cancelWriting()
      throw RecorderError.noFrames
    }
    let endPTS = CMTimeMaximum(end, lastPTS)
    queue.sync {
      input.markAsFinished()
      writer.endSession(atSourceTime: endPTS)
    }
    await writer.finishWriting()
    guard writer.status == .completed else {
      throw RecorderError.writer(writer.error?.localizedDescription ?? "unknown error")
    }
    return Recording(
      mp4: url, thumbs: thumbs, duration: (endPTS - firstPTS).seconds,
      pointSize: selection.rect.size, pixelSize: pixelSize, fps: fps)
  }

  /// Stops capture and deletes the MP4.
  func cancel() async {
    queue.sync { cancelled = true }
    if let stream { try? await stream.stopCapture() }
    stream = nil
    queue.sync { writer?.cancelWriting() }
    try? FileManager.default.removeItem(at: url)
  }
}
