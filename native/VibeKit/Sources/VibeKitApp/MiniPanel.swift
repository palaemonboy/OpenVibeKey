// MiniPanel.swift — 菜单栏迷你面板：设备状态/配置切换/输入设备列表/开机启动/打开设置。
// 纯搬运自 VibeKitApp.swift。
import SwiftUI
import AppKit
import VibeKitAudio
import ServiceManagement

// 菜单栏迷你面板：高频操作不用开设置窗。状态全部来自共享的 VibeVM，不新增任何设备命令。
struct MiniPanel: View {
    @ObservedObject private var language = AppLanguage.shared
    @EnvironmentObject var vm: VibeVM
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var launchAtLogin = false
    // register()/unregister() 抛错时（例如用户在"系统设置 → 登录项"里禁用过本 App）存下原因，
    // 在开关下方提示；不然界面表现就是"点了勾选框，它自己弹回去了"，没有任何线索。
    @State private var loginError: LocalizedMessage?
    // SMAppService 只在 .app bundle 内有效；swift run 场景下 bundleIdentifier 为 nil。
    private var inBundle: Bool { Bundle.main.bundleIdentifier != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 分段设备列表 +
            // 带图标的底部菜单行，替换掉之前"连接状态在最上、麦克风挤中间"的紧凑单列布局。
            // 数据仍全部来自 VibeVM，没有新增设备命令或音频 API。
            // 顶部摘要卡（当前设备名 + 类型图标 + 锁按钮）已删除——内容与下面"输入设备"列表
            // 里当前设备那一行完全重复（同样有名称/图标/锁按钮，选中态还有高亮），见
            // .superpowers/sdd/2026-09-03-milestone5-menubar-packaging/remove-summary-card-report.md。
            HStack(spacing: 6) {
                Circle().fill(vm.connected ? Color.green : Color.secondary).frame(width: 7, height: 7)
                Text(vm.connected ? L("已连接") : vm.linkPresent ? L("等待 AU05 开机") : L("未连接"))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer()
                if vm.connected {
                    Text(vm.charging ? "\(vm.battery) ⚡" : vm.battery)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if vm.connected {
                HStack {
                    Text(L("配置")).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { vm.activeName }, set: { vm.loadProfile($0) })) {
                        ForEach(vm.profileNames, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().fixedSize()
                }
            } else {
                Button(L("连接设备"), action: vm.connect)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            Divider()
            // 输入设备段：段标题 + 刷新按钮 + 逐行列表，取代原来"一个 Picker + 一个锁按钮"。
            // 数据/操作仍是同一套 VibeVM 成员：currentInput/inputDevices/setInput/enforceVibeMic/
            // enforceTargetName/setEnforce/canEnforce，不新增任何设备命令或音频 API。
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("输入设备")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { vm.refreshAudio() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    }
                    .buttonStyle(GhostButtonStyle()).help(L("刷新设备列表"))
                }
                VStack(spacing: 4) {
                    ForEach(vm.inputDevices) { d in deviceRow(d) }
                }
            }
            // MenuBarExtra 的 content 是懒加载的：每次弹出面板都会重新构建这棵视图树，
            // 所以 .onAppear 天然会随每次弹出都触发一次，用来刷新设备列表——覆盖插拔场景，
            // 不会出现"面板打开着但列表是旧的"。
            .onAppear { vm.refreshAudio() }
            Divider()
            // 底部改成三行带前导图标的菜单行（取代修复轮次 1 那个"checkbox + 两个图标"的单行）。
            VStack(alignment: .leading, spacing: 2) {
                LanguageMenu()
                Toggle(L("开机时启动"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                            loginError = nil
                        } catch {
                            // 注册失败（未打包、或系统拒绝，比如用户在系统设置里禁用过本 App）时
                            // 把开关弹回真实状态，不留假象，同时留下原因供用户诊断。
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                            loginError = LocalizedMessage("开机启动设置失败：{0}", error.localizedDescription)
                        }
                    }))
                    .toggleStyle(.checkbox)
                    .disabled(!inBundle)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                if !inBundle {
                    Text(L("需打包成 .app 后可用")).font(.caption).foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                } else if let loginError {
                    Text(loginError.rendered()).font(.caption).foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                }
                menuRow(icon: "gearshape", title: L("打开设置…")) {
                    openWindow(id: "settings")
                    // LSUIElement 应用不会自动抢焦点，窗口可能开在别的窗后面。
                    NSApp.activate(ignoringOtherApps: true)
                    // 打开设置窗后把迷你面板收起，别让两层窗口叠在一起。
                    // @Environment(\.dismiss) 对 MenuBarExtra(.window) 的收起效果 macOS 14 起
                    // 才生效；部署目标是 13.0，13 上这行会退化成无操作（面板不会自动收起，但
                    // 不影响其余功能），可接受。
                    dismiss()
                }
                menuRow(icon: "power", title: L("退出 Open VibeKey")) { NSApp.terminate(nil) }
            }
        }
        .padding(12).frame(width: 288)
        .onAppear { launchAtLogin = (SMAppService.mainApp.status == .enabled) }
    }

    // 设备行：点主体 = 切到该设备（vm.setInput）；点右侧锁形按钮 = 锁定/解锁该设备。
    // "点未选中行的锁，应先选中再锁"：vm.setInput 是异步的（丢到后台队列切 CoreAudio，再回主线程
    // 刷新 currentInput），所以这里先切换、等一小段时间确认 currentInput 真的变成这台设备了再去锁，
    // 避免把切换前的旧设备当成锁定目标（延迟量级对齐 setEnforce 里已有的 0.3s CoreAudio 生效等待）。
    // 这里只是视图层编排 vm.setInput/vm.setEnforce 的调用顺序，没有改 VM 里已验证过的锁定语义。
    private func deviceRow(_ d: AudioInput) -> some View {
        let isCurrent = d.name == vm.currentInput
        // 判定"这一行是否被锁"（跟"当前默认输入是否被锁"是两码事，见 VibeVM.isLocked(_:)）
        // 优先按 uid 精确匹配（同名设备时不会两行同时高亮）；uid 还没解析出来（老数据刚升级、
        // 尚未命中过一次）时才退回名字比较——显示的仍是名字，不变。
        let isLockedHere = vm.isLocked(d)
        return HStack(spacing: 8) {
            Button { if !isCurrent { vm.setInput(d.id) } } label: {
                HStack(spacing: 8) {
                    // 修复轮次 4：选中态不再用行背景表达，改成类型图标着色——
                    // 是当前默认输入就用 accentColor，否则次要色，跟锁定态（背景+锁图标）分开判断。
                    Image(systemName: deviceTypeIcon(d.transport))
                        .font(.system(size: 12))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.name).font(.caption.weight(.medium)).lineLimit(1)
                        Text("\(L(d.transport)) · \(d.sampleRateText)").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                if isLockedHere {
                    vm.setEnforce(false)
                } else if isCurrent {
                    vm.setEnforce(true)
                } else {
                    vm.setInput(d.id)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if vm.currentInput == d.name { vm.setEnforce(true) }
                    }
                }
            } label: {
                Image(systemName: isLockedHere ? "lock.fill" : "lock.open")
                    .font(.system(size: 11))
                    .foregroundStyle(isLockedHere ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(GhostButtonStyle())
            .help(isLockedHere ? L("已锁定为 {0}，点击解锁", String(describing: d.name)) : L("锁定为 {0}", String(describing: d.name)))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        // 修复轮次 4：锁定态红→淡蓝(accentColor)；选中态不再上背景色（靠上面类型图标着色表达）。
        .background(isLockedHere ? Color.accentColor.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // 底部菜单行：统一样式（前导图标 + 文字，左对齐，无边框，悬停高亮），复用 GhostButtonStyle。
    private func menuRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 16)
                Text(title).font(.system(size: 12.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(GhostButtonStyle())
    }
}
