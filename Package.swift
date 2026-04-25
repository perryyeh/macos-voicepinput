// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoiceInputCore", targets: ["VoiceInputCore"]),
        .executable(name: "VoiceInput", targets: ["VoiceInput"]),
    ],
    targets: [
        .target(name: "VoiceInputCore", path: "Sources/VoiceInputCore"),
        .executableTarget(name: "VoiceInput", dependencies: ["VoiceInputCore"], path: "Sources/VoiceInput"),
        .testTarget(name: "VoiceInputTests", dependencies: ["VoiceInputCore"]),
    ]
)
