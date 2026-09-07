// swift-tools-version: 6.0
import PackageDescription

// 说明：本机为 Command Line Tools（无完整 Xcode），XCTest/Testing 不可用，
// 故用可执行 target「VibeKitOracle」做对拍校验（swift run VibeKitOracle）。
let package = Package(
    name: "VibeKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VibeKitCore", targets: ["VibeKitCore"]),
        .library(name: "VibeKitHID", targets: ["VibeKitHID"]),
        .executable(name: "VibeKitOracle", targets: ["VibeKitOracle"]),
        .executable(name: "VibeKitInfo", targets: ["VibeKitInfo"]),
        .executable(name: "VibeKitWrite", targets: ["VibeKitWrite"]),
        .library(name: "VibeKitHost", targets: ["VibeKitHost"]),
        .executable(name: "VibeKitHostProbe", targets: ["VibeKitHostProbe"]),
        .executable(name: "VibeKitApp", targets: ["VibeKitApp"]),
    ],
    targets: [
        .target(name: "VibeKitCore", resources: [.process("Resources")]),
        .target(name: "VibeKitHID", dependencies: ["VibeKitCore"]),
        .target(name: "VibeKitAudio", swiftSettings: [.swiftLanguageMode(.v5)]),
        // VibeKitHost — 主机侧动作（哨兵键池 / 全局热键 / App 枚举与激活）。
        // 单独成库而非塞进 VibeKitApp：executableTarget 没法被 runner 依赖，
        // 放进去 SentinelPool 与 HotKeyCenter 就永远测不了（设计文档 §10 要求可自动测）。
        // 用 Swift 5 语言模式：Carbon 事件回调是 C 函数指针 + 全局状态，
        // 与 Swift 6 严格并发检查冲突，且 VibeKitApp 本来就是 .v5。
        .target(name: "VibeKitHost", dependencies: ["VibeKitCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "VibeKitOracle",
            dependencies: ["VibeKitCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "VibeKitInfo", dependencies: ["VibeKitCore", "VibeKitHID", "VibeKitAudio"]),
        .executableTarget(name: "VibeKitWrite", dependencies: ["VibeKitCore", "VibeKitHID", "VibeKitAudio"]),
        .executableTarget(name: "VibeKitApp", dependencies: ["VibeKitCore", "VibeKitHID", "VibeKitAudio", "VibeKitHost"],
                          resources: [.process("Resources")],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "VibeKitHostProbe", dependencies: ["VibeKitHost"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
