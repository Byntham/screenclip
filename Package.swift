// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ScreenshotGif",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(
      name: "ScreenshotGif",
      path: "Sources/ScreenshotGif",
      swiftSettings: [.swiftLanguageMode(.v5)]
    )
  ]
)
