// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PersonalAssistant",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "AssistantCore", targets: ["AssistantCore"]),
        .executable(name: "capture-replay", targets: ["CaptureReplay"]),
    ],
    targets: [
        .target(name: "AssistantCore"),
        .executableTarget(name: "CaptureReplay", dependencies: ["AssistantCore"]),
        .testTarget(name: "AssistantCoreTests", dependencies: ["AssistantCore"]),
    ]
)
