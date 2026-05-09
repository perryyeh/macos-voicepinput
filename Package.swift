// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceIME",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoiceIMECore", targets: ["VoiceIMECore"]),
        .executable(name: "VoiceIME", targets: ["VoiceIME"]),
    ],
    targets: [
        .target(name: "VoiceIMECore", path: "Sources/VoiceIMECore"),
        .executableTarget(name: "VoiceIME", dependencies: ["VoiceIMECore"], path: "Sources/VoiceIME"),
        .testTarget(name: "VoiceIMETests", dependencies: ["VoiceIMECore"]),
    ]
)
