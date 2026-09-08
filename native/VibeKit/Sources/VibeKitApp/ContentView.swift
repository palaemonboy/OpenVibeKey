// ContentView.swift — 完整设置窗（三栏：设备图 / 快捷键 / 灯效+麦克风）及其全部子视图与 popover。
// 纯搬运自 VibeKitApp.swift。

// VibeKitApp — 现代化紧凑改版：毛玻璃三栏（左设备图 / 中快捷键 / 右灯效+系统麦克风）+ 右上信息与心跳。
// 设备 I/O 在后台队列执行，结果回主线程更新 UI。运行：swift run VibeKitApp
import SwiftUI
import AppKit
import VibeKitCore
import VibeKitAudio

// MARK: - 主界面

struct ContentView: View {
    @ObservedObject private var language = AppLanguage.shared
    // 状态归属在 App 层（见 VibeKitApp）：迷你面板与设置窗必须共用同一个 VibeVM，
    // 否则两个实例会各开一次 HID、各跑一份心跳，争抢厂商口。
    @EnvironmentObject var vm: VibeVM
    @EnvironmentObject var mic: MicMeter
    @State private var showInfoPop = false
    @State private var confirmReboot = false
    @State private var showPowerPop = false
    @State private var showSelfTest = false
    @State private var showDialCal = false
    @State private var showProfiles = false
    @State private var profileName = ""
    @State private var savedFlash = false
    // 隐藏调试模式：连点 ℹ️(设备信息)5 次解锁「标定」。本会话有效，重启复位。
    @State private var infoTaps = 0
    @State private var debugUnlocked = false

    var body: some View {
        ZStack {
            // 背景：柔和渐变 + 一层低透明度毛玻璃，让设备图直接浮在其上。
            LinearGradient(colors: [Color.accentColor.opacity(0.14), Color(nsColor: .windowBackgroundColor)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            Rectangle().fill(.ultraThinMaterial).opacity(0.35).ignoresSafeArea()

            VStack(spacing: 16) {
                header
                // 哨兵提示与离线绑定区块都必须在**所有**连接状态下渲染。
                // 主机侧热键的寿命跟的是进程，不是设备：设备离线时那几个 ⌃⌥⌘F9 照样被本
                // 进程全局吃掉。早先这两样都埋在只有 vm.connected 才渲染的快捷键卡里，
                // 于是设备一离线（或厂商口被 CLI 抢了导致误判离线），用户既看不到
                // 「找不到该 App」这类只有离线才会触发的提示，也没有任何办法解绑——只能退 App。
                sentinelNoticeBanner
                if !vm.connected { offlineAppBindingsCard }
                if vm.connected {
                    HStack(alignment: .top, spacing: 16) {
                        deviceColumn(showHint: true)
                        shortcutsCard.frame(maxWidth: .infinity)
                        VStack(spacing: 14) { ledCard; micTuneCard; micCard }.frame(width: language.resolved == .english ? 300 : 264)
                    }
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                            removal: .opacity))
                } else if vm.linkPresent {
                    // 连接器在位但 AU05 未开机：等待态，心跳持续探测，开机后自动加载。
                    HStack(alignment: .top, spacing: 16) {
                        deviceColumn(showHint: false)
                        waitingForDevice.frame(maxWidth: .infinity)
                    }
                    .transition(.opacity)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        deviceColumn(showHint: false)
                        disconnected.frame(maxWidth: .infinity)
                    }
                    .transition(.opacity)
                }
            }
            .padding(20)
            .frame(width: language.resolved == .english ? 1020 : 900, alignment: .top)   // 固定内容宽度；高度随内容
        }
        .coordinateSpace(name: "root")
        .overlayPreferenceValue(AnchorFrames.self) { frames in
            // 旋钮 + 三个按键各一条灰线，指向对应标签；竖直段从上到下依次右移，
            // 分层（第一/二/三/四层）、互不重合、互不相交。
            if vm.connected, let imgF = frames["devimg"] {
                // 竖直段只能落在「设备图右缘 → 目标标签左侧」这条走廊里，而走廊只有三十几点宽。
                // 早先四条 lane 写死成 +0/+16/+38/+66，最右那两条超出走廊，被 ConnectorOverlay
                // 里那道 `min(…, end.x - 6)` 一起夹到同一个 x —— btn1 与 btn2 的竖直段完全重合，
                // 看起来是一条从「按钮 1」直通「按钮 2」的长线。改成按走廊实际宽度均分：
                // 间距随布局自适应，钳位退回成兜底，不会再把两条夹成一条。
                let laneOrder = ["dial", "btn3", "btn2", "btn1"]   // 从左到右；源越靠上，lane 越靠右
                let left = imgF.maxX + 6
                // 右界只看三个按钮标签——它们的 lane 最靠右，走廊由它们定。旋钮 lane 在最左，
                // 不该被「旋钮」标签自己的位置拖着一起收窄。
                let btnMinX = ["btn1", "btn2", "btn3"].compactMap { frames["label:\($0)"]?.minX }.min()
                let right = max((btnMinX ?? left + 60) - 12, left + 24)
                let step = (right - left) / CGFloat(laneOrder.count - 1)
                ForEach(["dial", "btn1", "btn2", "btn3"], id: \.self) { id in
                    if let fromBox = DeviceGeom.rect(id, in: imgF),
                       let to = frames["label:\(id)"],
                       let lane = laneOrder.firstIndex(of: id) {
                        ConnectorOverlay(from: fromBox, to: to, laneX: left + step * CGFloat(lane))
                    }
                }
            }
        }
        .preferredColorScheme(vm.colorScheme)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: vm.connected)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: vm.linkPresent)
        // LSUIElement 应用关窗后整个 App 在 Dock/⌘Tab 里完全隐形，用户无法再回到窗口点"停止"，
        // 所以电平表必须在窗口消失时自己停，否则 AVAudioEngine 和麦克风占用会一直挂着退不掉。
        .onDisappear { mic.stop() }
    }

    // 左：设备图（去底照片直接浮在背景毛玻璃上，无边框底板）。
    func deviceColumn(showHint: Bool) -> some View {
        VStack(spacing: 10) {
            DeviceImageView().padding(.vertical, 6)
        }
        .padding(.horizontal, 8)
    }

    // 顶栏：品牌 · 右上设备信息（独立一行防截断）+ 连接心跳 + 主题 + 连接
    var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "dial.medium.fill")
                    .font(.system(size: 26)).foregroundStyle(Color.accentColor)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 6)
                Text("Open VibeKey").font(.system(.title2, design: .rounded).weight(.bold))
                Spacer()
                if vm.connected {
                    HStack(spacing: 6) {
                        HeartbeatBadge(beat: vm.heartbeat, active: true)
                        Text(L("已连接")).font(.caption).foregroundStyle(.green)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .help(L("连接正常，持续心跳"))
                }
                if vm.connected {
                    if savedFlash {
                        Text(L("已保存")).font(.caption).foregroundStyle(.green)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .transition(.opacity.combined(with: .scale))
                    }
                    Button { showProfiles.toggle() } label: {
                        Label(vm.activeName, systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(GhostButtonStyle()).help(L("配置：点开可加载/新增；界面改动自动存到当前配置"))
                    .popover(isPresented: $showProfiles, arrowEdge: .bottom) { profilePopover }
                    // 更新时间移到配置弹层内部（当前配置行 + 各配置分别显示），不再挂在按钮外面。
                }
                Button { vm.toggleScheme() } label: {
                    Image(systemName: vm.colorScheme == .dark ? "sun.max.fill" : "moon.fill").font(.system(size: 15))
                }
                .buttonStyle(GhostButtonStyle()).help(L("切换 日间 / 夜间"))
                LanguageMenu(compact: true)
                GitHubLink()
            }
            // 设备信息条：独立成行、右对齐，保证 SN / 固件完整显示。
            if vm.connected {
                HStack(spacing: 6) {
                    Spacer()
                    InfoChip(k: L("型号"), v: "AU05")
                    InfoChip(k: "SN", v: vm.sn, mono: true)
                    InfoChip(k: L("固件"), v: vm.firmware)
                    InfoChip(k: vm.charging ? L("⚡充电") : L("电量"), v: vm.battery, danger: !vm.charging && (vm.batteryPercent ?? 100) <= 20)
                    Button {
                        showInfoPop.toggle()
                        if !debugUnlocked {
                            infoTaps += 1
                            if infoTaps >= 5 {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { debugUnlocked = true }
                            }
                        }
                    } label: {
                        Image(systemName: "info.circle").font(.system(size: 15))
                    }
                    .buttonStyle(GhostButtonStyle()).help(L("查看完整设备信息"))
                    .popover(isPresented: $showInfoPop, arrowEdge: .bottom) { infoPopover }
                    // 电源设置：默认用户几乎不调，收进弹层而不是占着主界面。
                    Button { showPowerPop.toggle() } label: {
                        Image(systemName: "powerplug").font(.system(size: 15))
                    }
                    .buttonStyle(GhostButtonStyle()).help(L("电源：待机 / 休眠 / 重启"))
                    .popover(isPresented: $showPowerPop, arrowEdge: .bottom) { powerPopover }
                    // 按键自检：接收器转发通道卡死时，一切看起来都正常，只有按键出不来。
                    Button { showSelfTest.toggle() } label: {
                        Image(systemName: "stethoscope").font(.system(size: 15))
                    }
                    .buttonStyle(GhostButtonStyle()).help(L("按键自检：确认设备有没有真的发出按键"))
                    .popover(isPresented: $showSelfTest, arrowEdge: .bottom) { selfTestPopover }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.connected)
        .onChange(of: vm.saveTick) { _ in flashSaved() }
    }

    var infoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("设备信息")).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(.secondary)
            InfoRow(k: L("型号"), v: "AU05")
            InfoRow(k: L("序列号"), v: vm.sn, mono: true)
            InfoRow(k: L("固件"), v: vm.firmware)
            InfoRow(k: L("电量"), v: vm.charging ? L("{0} ⚡充电中", String(describing: vm.battery)) : vm.battery, tint: AnyShapeStyle(Color.accentColor))
            InfoRow(k: L("灯效模式"), v: [L("全灭"),L("全亮"),L("工作")][safe: vm.ledMode] ?? "—")
            InfoRow(k: L("灯效亮度"), v: [L("灭"),L("低"),L("高")][safe: vm.ledBrightness] ?? "—")
        }
        .padding(16).frame(width: 280)
    }

    var profilePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("配置")).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(.secondary)
            Text(L("界面上的改动会自动存到当前配置。可新增多套、随时加载。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(L("当前")).foregroundStyle(.secondary)
                Text(vm.activeName).fontWeight(.semibold)
                Spacer()
                Text(relativeAgo(vm.activeUpdatedAt)).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                TextField(L("新增配置名，如 工作"), text: $profileName).textFieldStyle(.roundedBorder)
                Button(L("新增")) { vm.addProfile(profileName); profileName = "" }
                    .buttonStyle(AccentButtonStyle()).fixedSize()
                    .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Divider()
            if vm.profileNames.isEmpty {
                Text(L("暂无配置")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(vm.profileNames, id: \.self) { n in
                    HStack(spacing: 8) {
                        Image(systemName: n == vm.activeName ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(n == vm.activeName ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(n).fontWeight(n == vm.activeName ? .semibold : .regular)
                            Text(vm.profileUpdated[n].map { L("更新于 ") + relativeAgo($0) } ?? L("尚未更新"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if n != vm.activeName {
                            Button(L("加载")) { vm.loadProfile(n) }.buttonStyle(GhostButtonStyle()).fixedSize()
                        }
                        Button { vm.deleteProfile(n) } label: { Image(systemName: "trash") }
                            .buttonStyle(GhostButtonStyle()).disabled(vm.profileNames.count <= 1)
                    }
                }
            }
        }
        .padding(16).frame(width: 320)
    }

    // 相对时间显示（刚刚 / N 分钟前 / N 小时前 / 日期）。
    func relativeAgo(_ d: Date?) -> String {
        guard let d else { return "" }
        let s = Date().timeIntervalSince(d)
        if s < 45 { return L("刚刚") }
        if s < 3600 { return L("{0} 分钟前", String(describing: Int(s / 60))) }
        if s < 43200 { return L("{0} 小时前", String(describing: Int(s / 3600))) }   // 12 小时内用相对时间
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: d)  // 超过 12 小时显示绝对时间
    }
    private func flashSaved() {
        // 必须推迟到下一轮 runloop 再开动画：saveTick 与用户刚点的控件(灯效模式等)在同一轮
        // 更新里，此处若直接 withAnimation，SwiftUI 会把这条 spring 套到那个控件的
        // transaction 上——表现就是「点了不动，等『已保存』冒出来才慢慢切过去」。
        // 推迟一轮后，用户那轮的 transaction.animation 为 nil，点击即时生效。
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { self.savedFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.4)) { self.savedFlash = false }
            }
        }
    }

    // 哨兵键相关提示（自动换键 / 池耗尽 / App 找不到）。点 × 关掉。
    // 挂在最外层 VStack 上而不是快捷键卡里：fireAppBinding 的「找不到「X」，它可能已被卸载」
    // 恰恰主要在离线时触发——那一下按键走的是 dongle 键盘通道，跟厂商口在不在线无关。
    @ViewBuilder
    var sentinelNoticeBanner: some View {
        if let notice = vm.sentinelNotice {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle.fill").foregroundStyle(.orange)
                Text(notice.rendered()).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { vm.sentinelNotice = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // 离线时的「打开 App」绑定一览。刻意做成只在离线出现的独立小卡，不动在线布局：
    // 在线时这些信息本来就在每行 ShortcutEditor 里，重复一遍只会打架。
    @ViewBuilder
    var offlineAppBindingsCard: some View {
        let rows = vm.appBindingRows
        if !rows.isEmpty {
            Card(title: L("「打开 App」绑定 · 仍在生效"), systemImage: "bolt.horizontal.circle",
                 subtitle: L("设备虽然没连上，但 Open VibeKey 还在运行——下面这些组合键仍然被本程序全局截获。")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { r in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(r.title).font(.system(.callout, design: .rounded).weight(.semibold))
                                    Text("→ \(r.appName)").font(.callout).foregroundStyle(Color.accentColor)
                                }
                                if r.dead {
                                    warnLine(L("哨兵键 {0} 没能注册上，此绑定当前不生效。", String(describing: r.sentinel)))
                                        .font(.caption2)
                                } else {
                                    Text(L("哨兵键 {0}", String(describing: r.sentinel))).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 6)
                            // 离线解绑：热键立刻注销，设备侧那串哨兵记进待清账，设备回来时补清。
                            Button(L("解绑")) { vm.unbindApp(slot: r.id) }
                                .buttonStyle(GhostButtonStyle()).fixedSize()
                        }
                    }
                    Text(L("设备连上后，已解绑槽位上残留的哨兵键会被自动清掉。"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    var shortcutsCard: some View {
        Card(title: L("快捷键 · 每键一个 · 离线生效"), systemImage: "keyboard") {
            VStack(spacing: 10) {
                dialGroup
                ForEach(vm.buttons.indices, id: \.self) { i in
                    ShortcutEditor(b: $vm.buttons[i],
                                   onApply: { vm.applyShortcut(i) },
                                   onClear: { vm.clearShortcut(i) },
                                   onBindApp: { app in
                                       vm.bindApp(slot: vm.buttons[i].id, bundleID: app.bundleID, displayName: app.name)
                                   },
                                   onUnbindApp: { vm.unbindApp(slot: vm.buttons[i].id) })
                    .equatable()
                }
            }
        }
    }

    // 旋钮：左转/右转/按下，各是一个复用按键协议的编辑器 + 标定入口。
    var dialGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // 连线落点报在图标上而不是「旋钮」二字上：这一行的最左元素是图标，
                // 报文字的话算出来的落点（文字左缘往左 6）正好压在图标身上。
                Image(systemName: "dial.medium").foregroundStyle(Color.accentColor).reportFrame("label:dial")
                Text(L("旋钮")).font(.system(.headline, design: .rounded))
                Spacer()
                // 标定属调试功能：默认隐藏，连点 ℹ️ 设备信息 5 次解锁。
                if debugUnlocked {
                    Button(L("标定")) { vm.runProbe(); showDialCal.toggle() }
                        .buttonStyle(GhostButtonStyle())
                        .popover(isPresented: $showDialCal, arrowEdge: .bottom) { dialCalPopover }
                        .transition(.opacity.combined(with: .scale))
                    Button(L("唤醒")) { vm.wakeDevice() }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(vm.waking)
                        .help(L("闲置后厂商口可能对所有命令无响应，发一条心跳试探能否唤醒"))
                        .transition(.opacity.combined(with: .scale))
                    if vm.waking {
                        Text(L("唤醒中…")).font(.caption2).foregroundStyle(.secondary)
                    } else if let r = vm.wakeResult {
                        Text(r == .success ? L("已恢复") : L("仍无响应"))
                            .font(.caption2)
                            .foregroundStyle(r == .success ? .green : .secondary)
                    }
                }
            }
            ForEach(vm.dial.indices, id: \.self) { i in
                // 三个方向共用同一个编辑器；「打开 App」是否出现由 ShortcutEditor 按
                // APP_BINDABLE_SLOTS 自行判断，这里无脑接上即可（dialL/dialR 不在名单内）。
                ShortcutEditor(b: $vm.dial[i],
                               onApply: { vm.applyDial(i) },
                               onClear: { vm.clearDial(i) },
                               onBindApp: { app in
                                   vm.bindApp(slot: vm.dial[i].id, bundleID: app.bundleID, displayName: app.name)
                               },
                               onUnbindApp: { vm.unbindApp(slot: vm.dial[i].id) })
                    .equatable()
            }
        }
    }

    var dialCalPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("旋钮标定")).font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text(L("旋钮转动/按下会发出 index 3–15 的快捷键，但物理动作↔index 的对应需实测。用下面「写数字标记」最快："))
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("① 点「写数字标记」——把 index 3–9 分别设成数字键 3–9（物理按键 0/1/2 不动）。"))
                Text(L("② 光标放进任意输入框（备忘录/搜索框）。"))
                Text(L("③ 分别 左转 / 右转 / 按下 旋钮，看各自打出哪个数字，那就是该动作的 index。"))
                Text(L("④ 把三个 index 填到下方，再回到旋钮卡片给每个方向配上真正想要的键。"))
            }
            .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button(L("写数字标记 3–9"), action: vm.writeDialMarkers).buttonStyle(AccentButtonStyle())
                Button(L("探测 index 0–9"), action: vm.runProbe).buttonStyle(GhostButtonStyle())
            }
            if !vm.probe.isEmpty {
                VStack(spacing: 3) {
                    ForEach(vm.probe) { p in
                        HStack {
                            Text("index \(p.id)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            Spacer()
                            Text(p.disp.rendered()).font(.caption.monospaced())
                        }
                    }
                }
                .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Divider()
            ForEach(0..<3) { i in
                Stepper(value: Binding(get: { vm.dialIdx[i] }, set: { vm.setDialIndex(i, $0) }), in: 0...15) {
                    HStack {
                        Text([L("左转"), L("右转"), L("按下")][i])
                        Spacer()
                        Text("index \(vm.dialIdx[i])").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16).frame(width: 340)
    }

    var ledCard: some View {
        Card(title: L("灯效 · 全局"), systemImage: "lightbulb.fill", subtitle: L("模式 / 亮度")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("灯效模式")).frame(width: language.resolved == .english ? 76 : 64, alignment: .leading).foregroundStyle(.secondary)
                    // 与 ShortcutEditor 同理：只在用户交互处写设备，不用 onChange ——
                    // 否则连接时按本地配置回填也会被当成改动，触发写设备 + autosave。
                    Picker("", selection: Binding(
                        get: { vm.ledMode }, set: { vm.ledMode = $0; vm.applyLedMode() })) {
                        Text(L("全灭")).tag(0); Text(L("全亮")).tag(1); Text(L("工作")).tag(2)
                    }.pickerStyle(.segmented).labelsHidden()
                }
                HStack {
                    Text(L("灯效亮度")).frame(width: language.resolved == .english ? 76 : 64, alignment: .leading).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { vm.ledBrightness }, set: { vm.ledBrightness = $0; vm.applyLedBrightness() })) {
                        Text(L("灭")).tag(0); Text(L("低")).tag(1); Text(L("高")).tag(2)
                    }.pickerStyle(.segmented).labelsHidden()
                }
                .disabled(vm.ledMode != 1)   // 仅「全亮」可调亮度
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("工作模式各灯")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(0..<4, id: \.self) { i in
                        HStack {
                            Text([L("按钮 1"), L("按钮 2"), L("按钮 3"), L("旋钮")][i])
                                .frame(width: 52, alignment: .leading).foregroundStyle(.secondary).font(.callout)
                            Picker("", selection: Binding(
                                get: { vm.ledTypes[i] },
                                set: { vm.ledTypes[i] = $0; vm.applyLedType(i) })) {
                                Text(L("灭")).tag(0); Text(L("常亮")).tag(1)
                                if i == 0 { Text(L("呼吸")).tag(2) }   // 仅 btn1(麦克风指示灯)固件支持持续呼吸
                            }.pickerStyle(.segmented).labelsHidden()
                        }
                    }
                }
                .disabled(vm.ledMode != 2)                 // 仅「工作」模式可单独调各灯
                .opacity(vm.ledMode != 2 ? 0.45 : 1)
            }
        }
    }

    // 电源：待机/休眠时长 + 重启。都是设备侧设置，写进去后离线/无线一样生效。
    // 档位用预设值而非自由输入 —— 填出离谱的秒数会把设备搞成秒睡或永不睡。
    static let standbyChoices: [(String, Int)] = [("1 分钟", 60), ("3 分钟", 180), ("5 分钟", 300), ("10 分钟", 600), ("30 分钟", 1800)]
    static let sleepChoices: [(String, Int)] = [("10 分钟", 600), ("30 分钟", 1800), ("1 小时", 3600), ("2 小时", 7200), ("4 小时", 14400)]

    var powerPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("电源")).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text(L("待机时长")).frame(width: language.resolved == .english ? 76 : 64, alignment: .leading).foregroundStyle(.secondary)
                Spacer()
                // 与灯效同理：只在用户交互处写设备，不用 onChange，避免回填被当成改动。
                Picker("", selection: Binding(
                    get: { vm.standbyTime }, set: { vm.standbyTime = $0; vm.applyStandbyTime() })) {
                    ForEach(Self.standbyChoices, id: \.1) { Text(L($0.0)).tag($0.1) }
                    // 设备当前值不在预设档里时补一项，避免 Picker 选中态丢失。
                    if !Self.standbyChoices.contains(where: { $0.1 == vm.standbyTime }) {
                        Text(L("{0} 秒", String(describing: vm.standbyTime))).tag(vm.standbyTime)
                    }
                }.labelsHidden().fixedSize()
            }
            HStack {
                Text(L("休眠时长")).frame(width: language.resolved == .english ? 76 : 64, alignment: .leading).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { vm.sleepTime }, set: { vm.sleepTime = $0; vm.applySleepTime() })) {
                    ForEach(Self.sleepChoices, id: \.1) { Text(L($0.0)).tag($0.1) }
                    if !Self.sleepChoices.contains(where: { $0.1 == vm.sleepTime }) {
                        Text(L("{0} 秒", String(describing: vm.sleepTime))).tag(vm.sleepTime)
                    }
                }.labelsHidden().fixedSize()
            }
            Text(L("待机＝息屏低功耗，按键可唤醒；休眠更深一级。调长更跟手，代价是耗电。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Button(vm.rebooting ? L("正在重启…") : L("重启设备")) { confirmReboot = true }
                    .buttonStyle(GhostButtonStyle()).fixedSize().disabled(vm.rebooting)
                Text(L("会短暂断连，自动重连")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14).frame(width: language.resolved == .english ? 300 : 264)
        .alert(L("重启 VibeKey？"), isPresented: $confirmReboot) {
            Button(L("取消"), role: .cancel) {}
            Button(L("重启"), role: .destructive) { vm.rebootDevice() }
        } message: {
            Text(L("设备会断开几秒后自动重连。已写入设备的快捷键和设置不受影响。"))
        }
    }

    // 按键自检弹层。回答两个一直混在一起的问题：设备到底发没发键；以及若发了，
    // 为什么你仍觉得「没反应」——多半是配的键在当前应用里本来就没有可见效果。
    var selfTestPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("按键自检")).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(.secondary)
            Divider()
            switch vm.selfTestPhase {
            case .idle:
                Text(L("检查设备有没有真的把按键发给电脑。接收器的转发通道偶尔会卡死——那时 USB、配置、电量全都正常，唯独按键一个都出不来。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L("开始自检")) { vm.startSelfTest() }
                    .buttonStyle(GhostButtonStyle()).fixedSize().disabled(!vm.connected)
                if !vm.connected {
                    Text(L("设备未在线，请先长按开机。")).font(.caption2).foregroundStyle(.orange)
                }
            case .waiting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("请现在按一下 VibeKey 任意键，或转一下旋钮")).font(.callout)
                }
                Text(L("剩余 {0} 秒", String(describing: vm.selfTestRemaining))).font(.caption).foregroundStyle(.secondary)
                Button(L("取消")) { vm.cancelSelfTest() }.buttonStyle(GhostButtonStyle()).fixedSize()
            case .done(let v):
                selfTestResult(v)
                Button(L("再测一次")) { vm.startSelfTest() }.buttonStyle(GhostButtonStyle()).fixedSize()
            }
        }
        .padding(14).frame(width: 300)
    }

    @ViewBuilder
    func selfTestResult(_ v: VibeKitSelfTestVerdict) -> some View {
        switch v {
        case .reportsSeen(let n):
            Text(L("✅ 设备正常，窗口内发出了 {0} 个按键报告。", String(describing: n))).font(.callout).foregroundStyle(.green)
            Text(L("如果你仍觉得某个键「没反应」，那是它配的功能在当前应用里没有可见效果——比如 ⌘. 或 Esc 在桌面上按下去本来就什么都不会发生。当前配置："))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(vm.buttons) { b in
                    Text("· \(L(b.title)): \(localizedShortcut(b))").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(vm.dial) { d in
                    Text("· \(L(d.title)): \(localizedShortcut(d))").font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .stuckForwarding:
            Text(L("❌ 设备在线（电量读得到），但一个按键报告都没发出。")).font(.callout).foregroundStyle(.red)
            Text(L("这是接收器的按键转发通道卡死了。**把 2.4G 接收器拔下来再插回去**即可恢复，配置和快捷键都不会丢。"))
                .font(.caption).fixedSize(horizontal: false, vertical: true)
        case .deviceOffline:
            Text(L("无法判定：设备当前不在线。")).font(.callout).foregroundStyle(.orange)
            Text(L("设备不在线时零上报什么都证明不了。请先长按开机，再重新自检。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .counterReset:
            Text(L("基线作废：接收器中途重新枚举过。")).font(.callout).foregroundStyle(.orange)
            Text(L("刚刚发生过拔插或掉线重连，系统的上报计数已归零。请重新自检。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .probeUnavailable:
            Text(L("自检不可用：读不到系统的 HID 上报计数。")).font(.callout).foregroundStyle(.secondary)
            Text(L("此状态计数在系统更新后可能不可用。设备本身不受影响。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // 麦克风调试：开关 / 降噪 / 系统输入音量(增益)。放在「灯效 · 全局」下面。
    var micTuneCard: some View {
        Card(title: L("麦克风"), systemImage: "waveform", subtitle: L("开关 / 降噪 / 收音大小")) {
            VStack(alignment: .leading, spacing: 14) {
                // 同灯效：只在用户交互处写设备，避免回填触发写-存循环。
                Toggle(L("设备麦克风开关"), isOn: Binding(
                    get: { vm.micOn }, set: { vm.micOn = $0; vm.applyMic() }))
                    .toggleStyle(.switch).tint(Color.accentColor)
                HStack {
                    Text(L("降噪")).frame(width: language.resolved == .english ? 76 : 64, alignment: .leading).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { vm.nrLevel }, set: { vm.nrLevel = $0; vm.applyNR() })) {
                        Text(L("关")).tag(0); Text(L("低")).tag(1); Text(L("中")).tag(2); Text(L("高")).tag(3)
                    }.pickerStyle(.segmented).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("收音音量")).foregroundStyle(.secondary)
                        Spacer()
                        Text(vm.inputVolSupported ? "\(Int(vm.inputVol * 100))%" : L("不支持"))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Slider(value: $vm.inputVol, in: 0...1, onEditingChanged: { editing in if !editing { vm.applyInputVol() } })
                        .tint(Color.accentColor).disabled(!vm.inputVolSupported)
                }
            }
        }
    }

    var micCard: some View {
        Card(title: L("系统麦克风"), systemImage: "mic.fill", subtitle: L("当前录音设备")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(isVibeMic(vm.currentInput) ? Color.green : Color.orange).frame(width: 9, height: 9)
                    Text(vm.currentInput)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(isVibeMic(vm.currentInput) ? .green : .orange)
                        .lineLimit(1)
                    Spacer()
                    Button(L("刷新"), action: vm.refreshAudio).buttonStyle(GhostButtonStyle())
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: vm.currentInput)
                HStack {
                    Text(L("切换到")).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { vm.inputDevices.first { $0.name == vm.currentInput }?.id ?? 0 },
                        set: { vm.setInput($0) })) {
                        ForEach(vm.inputDevices) { d in Text(d.name).tag(d.id) }
                    }.labelsHidden()
                }
                // 修复轮次 2：锁的不再是写死的 AU05，而是"当前选中的设备"——文案和状态判断
                // 都改成读 vm.enforceTargetName/currentInput，不再用 isVibeMic() 判断。
                Toggle(vm.enforceVibeMic ? L("插着时锁定为「{0}」", String(describing: vm.enforceTargetName)) : L("插着时锁定为「{0}」", String(describing: vm.currentInput)),
                       isOn: Binding(get: { vm.enforceVibeMic }, set: { vm.setEnforce($0) }))
                    .toggleStyle(.switch).tint(Color.accentColor)
                    .disabled(!vm.canToggleLock)
                Text(vm.enforceVibeMic
                     ? (vm.isLockedOnCurrent
                        ? L("🔒 已锁定：当前正用「{0}」（被切走会自动切回）", String(describing: vm.enforceTargetName))
                        : L("🔒 锁定中…正在切回「{0}」", String(describing: vm.enforceTargetName)))
                     : L("未锁定：系统输入可自由切换"))
                    .font(.caption)
                    .foregroundStyle(vm.enforceVibeMic ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: vm.enforceVibeMic)
                Divider()
                HStack(spacing: 12) {
                    Button(mic.running ? L("停止") : L("测试")) { mic.running ? mic.stop() : mic.start() }
                        .buttonStyle(GhostButtonStyle())
                    LevelBar(level: Double(mic.level))
                }
                if mic.permissionDenied { Text(L("需麦克风权限")).font(.caption).foregroundStyle(.red) }
                if mic.needsBundle { Text(L("电平测试需打包成 .app 后可用")).font(.caption).foregroundStyle(.orange) }
            }
        }
    }

    var disconnected: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 92, height: 92)
                    .scaleEffect(vm.connecting ? 1.12 : 1)
                    .animation(vm.connecting ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                               value: vm.connecting)
                Image(systemName: vm.connecting ? "cable.connector" : "cable.connector.horizontal")
                    .font(.system(size: 38)).foregroundStyle(Color.accentColor)
            }
            if vm.connecting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("正在连接 VibeKey…")).font(.system(.headline, design: .rounded)).foregroundStyle(.secondary)
                }
            } else {
                Text(L("未连接")).font(.system(.title3, design: .rounded).weight(.semibold))
                Text(L("把 VibeKey 的连接器插上 · 关闭原厂 App，然后点下方「连接设备」"))
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 340)
                Button(L("连接设备"), action: vm.connect).buttonStyle(AccentButtonStyle()).controlSize(.large)
                if vm.status.contains("失败") {
                    Text(L(vm.status)).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44).padding(.horizontal, 28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.connecting)
    }

    // 连接器在位但设备未开机：等待态。心跳每 3s 持续探测，AU05 开机后自动读取并加载。
    var waitingForDevice: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.12)).frame(width: 92, height: 92)
                Image(systemName: "powersleep")
                    .font(.system(size: 38)).foregroundStyle(.orange)
            }
            // 标题不能写「等待 AU05 开机」：那是在断言一件我们判定不了的事。
            // 厂商口静默有两种原因——设备真没开机，和设备开着但**待机**（闲置约 300 秒后
            // 厂商口对所有命令无响应，而按键照常生效，因为快捷键走的是 dongle 键盘通道）。
            // 两者在这里长得一模一样，无从区分。早先那句「请开启 AU05（长按开机）」在待机
            // 这种更常见的情况下是**错的指引**：设备本来就开着，照做没有任何用。
            Text(L("AU05 没有响应")).font(.system(.title3, design: .rounded).weight(.semibold))
            // 用显式的多行结构，不靠 Text 的 markdown/换行解析——那套行为不值得赌。
            VStack(alignment: .leading, spacing: 6) {
                Text(L("连接器已插好，但设备的配置通道没有回应。两种可能："))
                HStack(alignment: .top, spacing: 6) {
                    Text("·")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("设备在待机")).fontWeight(.semibold).foregroundStyle(.primary)
                        Text(L("转一下旋钮或按一下按键就能唤醒。待机时按键照常生效，休眠的只是配置通道。"))
                    }
                }
                HStack(alignment: .top, spacing: 6) {
                    Text("·")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("设备没开机")).fontWeight(.semibold).foregroundStyle(.primary)
                        Text(L("长按开机。"))
                    }
                }
                Text(L("恢复后会自动读取序列号 / 固件 / 电量并加载你的配置。"))
            }
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 380, alignment: .leading)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("持续检测中…")).font(.caption).foregroundStyle(.secondary)
            }
            // 唤醒按钮必须在这里。早先它只存在于 dialGroup 里、还锁在连点 5 次的调试开关后面，
            // 而 dialGroup 只在**已连接**时渲染——于是它在唯一需要它的离线态里根本不存在，
            // 用户面对一句错误的提示、手上一个可用的按钮都没有。
            // wakeDevice 在这个状态下是可调的：goOffline 只清 connected，不会把 dev 置空。
            HStack(spacing: 8) {
                Button(L("尝试唤醒")) { vm.wakeDevice() }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(vm.waking)
                    .help(L("发一条心跳试探能否把待机的配置通道叫醒；叫不醒就得物理转一下旋钮"))
                Button(L("重新检测"), action: vm.beat).buttonStyle(GhostButtonStyle())
            }
            if vm.waking {
                Text(L("唤醒中…")).font(.caption).foregroundStyle(.secondary)
            } else if let r = vm.wakeResult {
                // 叫不醒是常态而非故障：待机深了就只能物理唤醒。如实说下一步该做什么。
                Text(r == .success ? L("已恢复") : L("仍无响应——请转一下旋钮或按一下按键"))
                    .font(.caption)
                    .foregroundStyle(r == .success ? .green : .orange)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44).padding(.horizontal, 28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.orange.opacity(0.18)))
    }
}
