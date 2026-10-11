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
        .target(name: "CQuickJS", exclude: ["vendor/LICENSE"],
                cSettings: [.define("_GNU_SOURCE"), .define("QUICKJS_NG_BUILD"),
                            .define("_CRT_SECURE_NO_WARNINGS"), .define("_CRT_NONSTDC_NO_DEPRECATE")]),
        .target(name: "CSQLite", cSettings: [.define("SQLITE_THREADSAFE", to: "1"),
                    .define("SQLITE_OMIT_LOAD_EXTENSION"), .define("SQLITE_ENABLE_FTS5")]),
        .target(name: "AssistantCore", dependencies: ["CQuickJS", "CSQLite"]),
        .executableTarget(name: "CaptureReplay", dependencies: ["AssistantCore"]),
        .testTarget(name: "AssistantCoreTests", dependencies: ["AssistantCore"]),
    ],
    cLanguageStandard: .c11
)

// Compile the same native EventKit bridge used by the iPhone app on Mac CI.
// These tests deliver synthetic, unsaved objects; no Calendar permission or
// personal account data is needed. Windows keeps the shared-core test suite.
#if os(macOS)
package.targets += [
    .target(name: "PlanningEventKitBridge", dependencies: ["AssistantCore"], path: "App/Device/PlanningEventKit"),
    .testTarget(name: "PlanningEventKitBridgeTests", dependencies: ["PlanningEventKitBridge", "AssistantCore"], path: "Tests/PlanningEventKitBridgeTests"),
]
#endif
