// VibeKitApp.swift — @main App 入口：场景结构（MenuBarExtra 迷你面板 + Window 设置窗）
// 与命令表自检。纯搬运自原巨型 VibeKitApp.swift（其余内容已拆到 VibeVM/ContentView/
// MiniPanel/Components/Constants.swift）。
import SwiftUI
import VibeKitCore
import VibeKitAudio

@main
struct VibeKitApp: App {
    @StateObject private var vm = VibeVM()
    @StateObject private var mic = MicMeter()
    @ObservedObject private var language = AppLanguage.shared

    init() {
        // 命令表自检：见 Task 1 的说明——加载失败不会崩溃，只会让写命令静默失败。
        let n = VibeKitCommands.specs.count
        FileHandle.standardError.write("[VibeKit] 命令表 \(n) 条\n".data(using: .utf8)!)
        // 不再调 setActivationPolicy：形态由 Info.plist 的 LSUIElement 决定。
    }

    var body: some Scene {
        MenuBarExtra {
            // 注意：这里不挂启动自动连接。MenuBarExtra 的 content 是懒加载的——只有 label 图标
            // 随 App 启动就渲染，content（本视图）要等用户第一次点开顶栏图标才会被构建，挂在
            // 这里的 .task 不会在启动时触发。启动自动连接见 VibeVM.init()。
            MiniPanel()
                .environmentObject(vm)
                .environment(\.locale, language.locale)
        } label: {
            Image(systemName: vm.connected ? "dial.medium.fill" : "dial.medium")
        }
        .menuBarExtraStyle(.window)     // 面板式，不是下拉菜单

        // Window 而非 WindowGroup：单实例，反复点「打开设置」不会开出多个窗。
        Window("Open VibeKey", id: "settings") {
            ContentView()
                .environmentObject(vm)
                .environmentObject(mic)
                .environment(\.locale, language.locale)
        }
        .windowResizability(.contentSize)
    }
}
