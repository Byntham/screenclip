// Finds out what T3 Code accepts on paste.
// Usage: swift paste-test.swift <input.gif>
// Builds a PNG sheet, a multi-page PDF of sheets, and an MP4 from the GIF,
// then puts each case on the clipboard one at a time.

import AppKit
import AVFoundation
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("sg-paste-test")
try? FileManager.default.removeItem(at: outDir)
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// Load frames and timestamps.
let src = CGImageSourceCreateWithURL(input as CFURL, nil)!
let total = CGImageSourceGetCount(src)
var frames: [CGImage] = []
var times: [Double] = []
var t = 0.0
for i in 0..<total {
  frames.append(CGImageSourceCreateImageAtIndex(src, i, nil)!)
  times.append(t)
  let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [String: Any]
  let g = p?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
  t += (g?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double) ?? 0.1
}
print("Loaded \(total) frames, \(String(format: "%.1f", t))s")

func evenlySpaced(_ count: Int) -> [Int] {
  (0..<count).map { $0 * (total - 1) / max(count - 1, 1) }
}

// Draws frames into a labeled grid.
func sheet(_ indices: [Int], numberFrom: Int, cols: Int) -> CGImage {
  let w = frames[0].width, h = frames[0].height, pad = 8, label = 28
  let rows = (indices.count + cols - 1) / cols
  let W = cols * w + (cols + 1) * pad
  let H = rows * (h + label) + (rows + 1) * pad
  let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
  let font = CTFontCreateWithName("Menlo-Bold" as CFString, 18, nil)
  for (n, i) in indices.enumerated() {
    let x = pad + (n % cols) * (w + pad)
    let top = H - (pad + (n / cols) * (h + label + pad))
    ctx.draw(frames[i], in: CGRect(x: x, y: top - label - h, width: w, height: h))
    let text = "#\(numberFrom + n)  t=\(String(format: "%.2f", times[i]))s"
    let attrs: [NSAttributedString.Key: Any] = [
      kCTFontAttributeName as NSAttributedString.Key: font,
      kCTForegroundColorAttributeName as NSAttributedString.Key:
        CGColor(red: 1, green: 0.85, blue: 0.3, alpha: 1),
    ]
    ctx.textPosition = CGPoint(x: x + 4, y: top - 20)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs)), ctx)
  }
  return ctx.makeImage()!
}

// Case files.
let pngURL = outDir.appendingPathComponent("capture.png")
let png = sheet(evenlySpaced(9), numberFrom: 1, cols: 3)
let dst = CGImageDestinationCreateWithURL(pngURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, png, nil)
CGImageDestinationFinalize(dst)

// PDF: 24 frames, 6 per page, 4 pages.
let pdfURL = outDir.appendingPathComponent("capture.pdf")
let pdfIdx = evenlySpaced(24)
var pdfCtx: CGContext?
for page in 0..<4 {
  let img = sheet(Array(pdfIdx[page * 6..<page * 6 + 6]), numberFrom: page * 6 + 1, cols: 3)
  var box = CGRect(x: 0, y: 0, width: img.width, height: img.height)
  if pdfCtx == nil { pdfCtx = CGContext(pdfURL as CFURL, mediaBox: &box, nil) }
  pdfCtx!.beginPage(mediaBox: &box)
  pdfCtx!.draw(img, in: box)
  pdfCtx!.endPage()
}
pdfCtx!.closePDF()

// MP4 from every frame.
let mp4URL = outDir.appendingPathComponent("capture.mp4")
let w = frames[0].width & ~1, h = frames[0].height & ~1
let writer = try! AVAssetWriter(outputURL: mp4URL, fileType: .mp4)
let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
  AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoIn, sourcePixelBufferAttributes: [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
  kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
])
writer.add(videoIn)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
for (i, frame) in frames.enumerated() {
  while !videoIn.isReadyForMoreMediaData { usleep(1000) }
  var pb: CVPixelBuffer?
  CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
  CVPixelBufferLockBaseAddress(pb!, [])
  let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
  ctx.draw(frame, in: CGRect(x: 0, y: 0, width: w, height: h))
  CVPixelBufferUnlockBaseAddress(pb!, [])
  adaptor.append(pb!, withPresentationTime: CMTime(seconds: times[i], preferredTimescale: 600))
}
videoIn.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print("Files in \(outDir.path)\n")

// Clipboard cases.
let pb = NSPasteboard.general
let cases: [(String, () -> Void)] = [
  ("A: PNG sheet as image data", {
    pb.setData(try! Data(contentsOf: pngURL), forType: .png)
  }),
  ("B: PNG sheet as a file", { pb.writeObjects([pngURL as NSURL]) }),
  ("C: PDF of 4 sheets as a file", { pb.writeObjects([pdfURL as NSURL]) }),
  ("D: MP4 as a file", { pb.writeObjects([mp4URL as NSURL]) }),
  ("E: PNG + MP4 as two files", { pb.writeObjects([pngURL as NSURL, mp4URL as NSURL]) }),
]
for (name, put) in cases {
  pb.clearContents()
  put()
  print("Clipboard now holds \(name)")
  print("Type the letter in T3 Code, paste, then press Enter here for the next case.")
  _ = readLine()
}
print("Done.")
