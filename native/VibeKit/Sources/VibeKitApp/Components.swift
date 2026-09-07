// Components.swift — 通用视图组件与样式：ShortcutEditor、帧上报(AnchorFrames/reportFrame)、
// 设备图几何(DeviceGeom)、毛玻璃卡片与按钮样式(Card/AccentButtonStyle/GhostButtonStyle)、
// 电平条/信息行/信息chip(LevelBar/InfoRow/InfoChip)、心跳徽标(RiseFade/HeartbeatBadge)、
// 连线(ConnectorOverlay)、设备图(DeviceImageView)。纯搬运自 VibeKitApp.swift。
import SwiftUI
import AppKit
import VibeKitHost

struct ShortcutEditor: View {
    @ObservedObject private var language = AppLanguage.shared
    @Binding var b: ButtonState
    let onApply: () -> Void
    let onClear: () -> Void
    /// 用户在选择器里选了一个 App。
    var onBindApp: (InstalledApp) -> Void = { _ in }
    /// 清除「打开 App」绑定。与 onClear 分开：清绑定要额外注销热键。
    var onUnbindApp: () -> Void = {}

    @State private var hover = false
    @State private var showAppPicker = false

    // 只有 btn1/2/3/dialP 能绑 App。旋钮左转/右转不行——连续转动会连发哨兵键。
    private var allowsAppBinding: Bool { APP_BINDABLE_SLOTS.contains(b.id) }
    private var isAppBound: Bool { b.appName != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L(b.title)).font(.system(.headline, design: .rounded)).reportFrame("label:\(b.id)")
                Spacer()
                Text(localizedShortcut(b))
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(b.current == "未设置" ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: b.current)
            }
            HStack(spacing: 8) {
                // 修饰键/主键任一改动即写入设备（无「应用」按钮）。只在用户交互处触发，
                // 不用 onChange —— 否则设备回读回填也会被当成改动，形成写-读-写循环。
                ForEach(MODS, id: \.token) { m in
                    let on = b.mods.contains(m.token)
                    Text(m.label)
                        .frame(width: 28, height: 26)
                        .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.06)),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .foregroundStyle(on ? Color.white : .primary)
                        .scaleEffect(on ? 1.08 : 1)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if on { b.mods.remove(m.token) } else { b.mods.insert(m.token) }
                            onApply()
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
                }
                // selection 用计算 Binding：绑了 App 就显示「打开 App」那一项。
                // 选中它只是开 sheet、不改状态，所以用户取消时 SwiftUI 重读 get 自然回退，
                // 不需要额外存一份「选中前的值」再回滚。
                Picker("", selection: Binding<String?>(
                    get: { isAppBound ? OPEN_APP_TOKEN : b.mainKey },
                    set: { v in
                        if v == OPEN_APP_TOKEN || v == OPEN_APP_PICK_TOKEN { showAppPicker = true }
                        else { b.mainKey = v; onApply() }
                    })) {
                    Text(L("主键")).tag(String?.none)
                    ForEach(MAIN_KEYS, id: \.token) { k in Text(L(k.label)).tag(String?.some(k.token)) }
                    if allowsAppBinding {
                        Divider()
                        if let name = b.appName {
                            // 打勾项保留 App 名：下拉收起时显示的就是它，勾也该指向真实状态。
                            // 换绑必须另起一项——点已打勾的项 SwiftUI 不回调 set，那项是死的。
                            Text(name).tag(String?.some(OPEN_APP_TOKEN))
                            Text(L("选择另一个 App…")).tag(String?.some(OPEN_APP_PICK_TOKEN))
                        } else {
                            Text(L("打开 App…")).tag(String?.some(OPEN_APP_TOKEN))
                        }
                    }
                }.labelsHidden().frame(width: 100).fixedSize()
                Spacer(minLength: 6)
                Button(L("清除")) { if isAppBound { onUnbindApp() } else { onClear() } }
                    .buttonStyle(GhostButtonStyle()).fixedSize()
            }
            if isAppBound {
                // 三种小字互不排斥，各说各的事，所以逐条判断而不是 if/else 三选一：
                //   · sentinelDead —— 热键没注册上，这条绑定当前完全不生效
                //   · appMissing   —— 上次激活失败，App 多半被卸载了
                //   · 都没有       —— spec §9 第一行的固有风险，如实常驻告知
                VStack(alignment: .leading, spacing: 3) {
                    if b.sentinelDead {
                        // 不写「被别的软件占着」——跨进程的占用这里根本检测不到（见
                        // HotKeyCenter.register 的注释）。能走到 sentinelDead 的只剩
                        // 池耗尽或 tokens 无效这类本进程内的原因。
                        warnLine(L("哨兵键 {0} 没能注册上，此绑定当前不生效。", String(describing: b.sentinelDisplay ?? "—")))
                    }
                    if b.appMissing {
                        warnLine(L("找不到该 App，可能已被卸载。重新选一个目标。"))
                    }
                    if !b.sentinelDead && !b.appMissing {
                        // 只报哨兵键是什么，不再附「退出后此键会传给前台 App」。
                        // 那句是设计时按机制推出来的（没有热键拦截，组合键理应落到前台），
                        // 但从未实测证实：⌃⌥⌘F9 打不出字符，靶子里看不见，唯一一次实测
                        // （Terminal + cat -v）什么都没出现。项目决定按「不漏」处理，不再验，
                        // 所以这句与结论相反的话不留在界面上。
                        //
                        // 留个话头：池里还有 ⌃⌥⌘0…9 十个数字哨兵，它们不像 F9 那样被
                        // Mission Control 占着，行为未必一致。真要较真得逐键实测。
                        Text(L("哨兵键 {0}", String(describing: b.sentinelDisplay ?? "—")))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(hover ? 0.14 : 0.06), lineWidth: 1))
        .shadow(color: .black.opacity(hover ? 0.12 : 0.05), radius: hover ? 8 : 4, x: 0, y: 3)
        .scaleEffect(hover ? 1.006 : 1)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hover)
        .sheet(isPresented: $showAppPicker) {
            AppPickerSheet { onBindApp($0) }
        }
    }
}

// 一个编辑器的 body 里，除了两个自己的 @State（hover / showAppPicker）就只读 b 和常量
// （MODS / MAIN_KEYS / APP_BINDABLE_SLOTS）。所以 b 没变时这一遍 body 必然产出同样的树，
// 建了也是白建 —— 而它一点都不便宜：主键下拉里 MAIN_KEYS 那 74 个 Text().tag() 是
// **每次 body 都全量重建**的（Picker 不管菜单开没开），实测单个 body 要 8~12ms。
//
// 六个编辑器共用一份 vm，父视图 ContentView 又依赖 vm 的一切：改一个键会重绘三遍，
// 连三秒一次的电量轮询也会把六个全建一遍。实测「选中一项」这一下要 ~150ms 主线程，
// 用户看到的就是一顿。声明 Equatable 后由 EquatableView 挡住，只有真的变了的那个会重建。
//
// 只比 b：@State 的变化走的是 SwiftUI 自己的失效路径，不受这里影响；闭包捕获的是 vm
// 与固定下标，跳过重建不会让它们变陈旧。
extension ShortcutEditor: Equatable {
    static func == (l: ShortcutEditor, r: ShortcutEditor) -> Bool { l.b == r.b }
}

/// 橙色警告小字（⚠️ + 文案）。行内与离线区块共用同一套观感。
@ViewBuilder
func warnLine(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 4) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        Text(text).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 帧上报（供设备图 ↔ 配置卡之间画连线）

struct AnchorFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
extension View {
    func reportFrame(_ id: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: AnchorFrames.self, value: [id: g.frame(in: .named("root"))])
        })
    }
}

// 设备图几何：热区使用原始 PNG 的像素坐标，绘制时统一映射到图片实际尺寸。
enum DeviceGeom {
    static let sourceSize = CGSize(width: 328, height: 968)
    static let imgW: CGFloat = 172
    static let imgH: CGFloat = imgW * sourceSize.height / sourceSize.width
    // 圆形部件正面边界，不包含向下投射的阴影。
    static let spots: [(id: String, bounds: CGRect)] = [
        ("dial", CGRect(x: 53, y: 166, width: 220, height: 220)),
        ("btn1", CGRect(x: 108, y: 440, width: 114, height: 114)),
        ("btn2", CGRect(x: 108, y: 601, width: 114, height: 114)),
        ("btn3", CGRect(x: 108, y: 761, width: 114, height: 114)),
    ]
    static func rect(_ id: String, in imgFrame: CGRect, adjust: CGSize = .zero) -> CGRect? {
        guard let s = spots.first(where: { $0.id == id }) else { return nil }
        let scaleX = imgFrame.width / sourceSize.width
        let scaleY = imgFrame.height / sourceSize.height
        // 兼容旧手动偏移：其单位是默认显示尺寸下的点，也随图片一起缩放。
        return CGRect(x: imgFrame.minX + s.bounds.minX * scaleX + adjust.width * imgFrame.width / imgW,
                      y: imgFrame.minY + s.bounds.minY * scaleY + adjust.height * imgFrame.height / imgH,
                      width: s.bounds.width * scaleX, height: s.bounds.height * scaleY)
    }
}

// MARK: - 设计组件（毛玻璃卡片 / 悬停按钮 / 电平条 / 信息 chip）

struct Card<Content: View>: View {
    @ObservedObject private var language = AppLanguage.shared
    let title: String
    var systemImage: String? = nil
    var subtitle: String? = nil
    var selected: Bool = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).foregroundStyle(Color.accentColor) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(.subheadline, design: .rounded).weight(.semibold)).kerning(0.3)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.07), lineWidth: selected ? 2 : 1))
        .shadow(color: selected ? Color.accentColor.opacity(0.25) : .black.opacity(0.10),
                radius: selected ? 14 : 12, x: 0, y: 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
    }
}

struct AccentButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.7 : (hover ? 1 : 0.88)),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .foregroundStyle(Color.white)
            .scaleEffect(configuration.isPressed ? 0.95 : (hover ? 1.04 : 1))
            .shadow(color: Color.accentColor.opacity(hover ? 0.45 : 0.22), radius: hover ? 8 : 4, x: 0, y: 2)
            .onHover { hover = $0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hover)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : (hover ? 0.1 : 0.05)),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed ? 0.95 : (hover ? 1.03 : 1))
            .onHover { hover = $0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hover)
    }
}

struct LevelBar: View {
    var level: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [.green, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geo.size.width * min(1, max(0, level))))
            }
        }
        .frame(height: 8)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: level)
    }
}

struct InfoRow: View {
    let k: String; let v: String; var mono = false; var tint: AnyShapeStyle = AnyShapeStyle(.primary)
    var body: some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).foregroundStyle(tint)
                .font(mono ? .system(.body, design: .monospaced) : .system(.body, design: .rounded))
        }
    }
}

// 顶栏紧凑信息 chip：key + value（电量低亮红）。
struct InfoChip: View {
    let k: String; let v: String; var danger = false; var mono = false
    var body: some View {
        HStack(spacing: 5) {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(mono ? .system(.caption, design: .monospaced) : .system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(danger ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(danger ? Color.red.opacity(0.5) : Color.primary.opacity(0.08)))
    }
}

// MARK: - 心跳徽标（绿点脉冲 + "+1" 上浮）

struct RiseFade: ViewModifier {
    @State private var up = false
    func body(content: Content) -> some View {
        content
            .offset(y: up ? -22 : 0)
            .opacity(up ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.1)) { up = true } }
    }
}

struct HeartbeatBadge: View {
    let beat: Int
    let active: Bool
    @State private var pops: [Int] = []
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(active ? Color.green : Color.secondary)
                .frame(width: 9, height: 9)
                .shadow(color: active ? .green.opacity(0.7) : .clear, radius: pulse ? 7 : 4)
                .scaleEffect(pulse ? 1.4 : 1)
            ForEach(pops, id: \.self) { id in
                Text("+1")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.green)
                    .modifier(RiseFade())
                    .id(id)
            }
            .offset(x: 12)
        }
        .frame(width: 12, height: 12)
        .onChange(of: beat) { _ in
            guard active else { return }
            let id = beat
            pops.append(id)
            // 同 flashSaved：动画推迟一轮，避免心跳恰好和用户点击落在同一轮 transaction 时污染对方。
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { pulse = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pulse = false }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { pops.removeAll { $0 == id } }
        }
    }
}

// MARK: - 连线（设备部件 → 对应配置卡的虚线引线）

// 从设备部件（右侧）直角走线，指向对应的文字标签（旋钮 / 按钮1/2/3）。
// laneX 为各自竖直段的 x：从上到下依次右移，形成分层、互不重合、互不相交。
struct ConnectorOverlay: View {
    let from: CGRect       // 设备部件圆（root 空间）
    let to: CGRect         // 目标文字标签（root 空间）
    let laneX: CGFloat     // 该条线竖直段所在的 x（分层）
    private let ink = Color.primary.opacity(0.32)
    var body: some View {
        let start = CGPoint(x: from.maxX + 3, y: from.midY)
        let end = CGPoint(x: to.minX - 6, y: to.midY)
        let lx = min(max(laneX, start.x + 6), end.x - 6)
        ZStack {
            Path { p in
                p.move(to: start)
                p.addLine(to: CGPoint(x: lx, y: start.y))
                p.addLine(to: CGPoint(x: lx, y: end.y))
                p.addLine(to: end)
            }
            .stroke(ink, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            Circle().fill(ink).frame(width: 4, height: 4).position(end)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 左侧设备图（去底透明照片 + 贴合灰圈，指向对应文字）

struct DeviceImageView: View {
    @ObservedObject private var language = AppLanguage.shared
    var adjust: [String: CGSize]
    private static let img: NSImage? = Bundle.module.url(forResource: "device", withExtension: "png").flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        let imgW = DeviceGeom.imgW, imgH = DeviceGeom.imgH
        ZStack(alignment: .topLeading) {
            if let im = Self.img {
                Image(nsImage: im).resizable().frame(width: imgW, height: imgH)
                    .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 10)
                    .reportFrame("devimg")
            } else {
                Rectangle().fill(Color.primary.opacity(0.06))
                    .frame(width: imgW, height: imgH)
                    .overlay(Text(L("设备图缺失")).font(.caption).foregroundStyle(.secondary))
                    .reportFrame("devimg")
            }
            ForEach(DeviceGeom.spots, id: \.id) { hs in
                if let bounds = DeviceGeom.rect(hs.id, in: CGRect(x: 0, y: 0, width: imgW, height: imgH),
                                                adjust: adjust[hs.id] ?? .zero) {
                    Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
                        .frame(width: bounds.width, height: bounds.height)
                        .offset(x: bounds.minX, y: bounds.minY)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: imgW, height: imgH)
    }
}

/// Only translate app-owned shortcut labels. User app and device names are never lookup keys.
func localizedShortcut(_ state: ButtonState) -> String {
    if let name = state.appName { return L("打开 App：{0}", name) }
    return L(state.current).replacingOccurrences(of: "空格", with: L("空格"))
}
