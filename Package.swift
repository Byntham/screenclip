// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ScreenClip",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(
      name: "ScreenClip",
      path: "Sources/ScreenClip",
      swiftSettings: [.swiftLanguageMode(.v5)]
    )
  ]
)
