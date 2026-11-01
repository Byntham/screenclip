import AppKit

let args = CommandLine.arguments

// Dev check: ScreenClip --pdf-from-gif <in.gif> <out.pdf> [maxFrames]
if args.count >= 4, args[1] == "--pdf-from-gif" {
  do {
    let result = try Exporter.pdfFromGIF(
      input: URL(fileURLWithPath: args[2]), output: URL(fileURLWithPath: args[3]),
      maxFrames: args.count >= 5 ? Int(args[4]) ?? 48 : 48)
    print("\(result.frames) frames on \(result.pages) pages -> \(result.url.path)")
    exit(0)
  } catch {
    print("error: \(error)")
    exit(1)
  }
}

MainActor.assumeIsolated {
  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  app.setActivationPolicy(.accessory)
  app.run()
}
