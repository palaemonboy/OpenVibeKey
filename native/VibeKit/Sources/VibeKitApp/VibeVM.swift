// VibeVM.swift — 设备/音频/持久化的核心 ObservableObject，及其直接相关类型
// （ButtonState / ProbeRow / Profile / retryRead）。纯搬运自 VibeKitApp.swift。
import SwiftUI
import AppKit
import CoreAudio
import VibeKitCore
import VibeKitHID
import VibeKitAudio
import VibeKitHost

struct ButtonState: Identifiable, Equatable {
    let id: String            // btn1/btn2/btn3 或 dialL/dialR/dialP
    var title: String
    var mods: Set<String> = []
    var mainKey: String? = nil
    var current: String = "读取中…"
    // 「打开 App」绑定的镜像。真身在 VibeVM.appBindings，这里只为渲染方便。
    // 非 nil 时 mods/mainKey 存的是哨兵组合，tokens 因此仍然给出该写进设备的东西。
    var appName: String? = nil
    var sentinelDisplay: String? = nil      // 如 "⌃⌥⌘F9"
    var appMissing = false                  // 上次激活失败：找不到该 App（多半被卸载了）
    // 哨兵热键此刻没注册上（池耗尽换不出新的、或 tokens 无效）。
    // 注意「被别的软件抢了」不在此列——那种占用检测不到，见 HotKeyCenter.register 的注释。
    // 这种绑定是**完全死的**：按按钮只会把组合键打给前台 App。
    // 必须常驻显示——早先只有一条可关闭的横幅，关掉就再无痕迹，行里照旧写着
    // 「打开 App：iTerm2 · 哨兵键 ⌃⌥⌘F9」，等于对着一个死绑定说它好着呢。
    var sentinelDead = false
    var tokens: [String] { MODS.map(\.token).filter { mods.contains($0) } + (mainKey.map { [$0] } ?? []) }
}

// 旋钮标定探测的一行（id = 0x50 命令的 index）。
struct ProbeRow: Identifiable { let id: Int; let disp: LocalizedMessage }

// 本地配置存档：三键 + 旋钮三方向的 tokens + 灯效 + 麦克风。存 UserDefaults。
struct Profile: Codable {
    var buttons: [[String]]      // btn1/2/3
    var dial: [[String]]         // 左/右/按
    var ledMode: Int
    var ledBrightness: Int
    var nrLevel: Int
    var micOn: Bool
    var micUiFlick: Bool?        // 可选：兼容旧存档
    var indicatorBreathe: Bool?  // 可选：指示灯呼吸
    var ledTypes: [Int]?         // 可选：工作模式各灯 type
    var standbyTime: Int?        // 可选：待机时长(秒)
    var sleepTime: Int?          // 可选：休眠时长(秒)
    var updatedAt: Double?       // 可选：最近更新时间（timeIntervalSince1970）
    // 可选：槽位 id → 「打开 App」绑定。哨兵组合键本身会随 buttons/dial 的 tokens 一起存，
    // 但「这个槽绑的是哪个 App」只能存在这里——设备读回表达不了它。
    var appBindings: [String: AppBinding]?
}

// 偶发单次读不到就重试几次（设备有时未在超时内响应）。后台 IO 队列调用，故为自由函数。
private func retryRead<T>(_ n: Int, _ f: () -> T?) -> T? { for _ in 0..<n { if let v = f() { return v } }; return nil }

@MainActor
final class VibeVM: ObservableObject {
    // MARK: 未打包→已打包 UserDefaults 域迁移（一次性）
    // `swift run` 跑开发版时没有 bundle id，UserDefaults 落在按可执行文件名分的域
    // "VibeKitApp"；打包成 .app 后 Info.plist 的 CFBundleIdentifier 是
    // com.openvibekey.app，UserDefaults 换了一个完全独立的域，旧数据（比如用户攒的
    // "工作" 配置存档）不会自动跟过来。这里把旧域里、新域缺的数据一次性搬过来。
    //
    // migratedDefaults 是 static let：Swift 保证同一进程只求值一次、在"第一次被访问"
    // 那一刻求值。下面所有直接读 UserDefaults 取默认值的 @Published 属性都改成读它而
    // 不是 UserDefaults.standard——这样无论哪个属性先完成初始化，第一次触碰到它就会
    // 触发迁移，迁移必定发生在任何配置被真正读取之前，且迁移结果本次启动就生效，不用
    // 等下一次启动（因为 UserDefaults.standard 是单例，migrate 里写完，本次的
    // .bool/.string/... 调用读到的就是已合并的值）。
    private static let migratedDefaults: UserDefaults = {
        migrateFromUnbundledDefaultsIfNeeded()
        return .standard
    }()

    private static func migrateFromUnbundledDefaultsIfNeeded() {
        let std = UserDefaults.standard
        let flag = "migratedFromUnbundled.v1"
        guard !std.bool(forKey: flag) else { return }
        defer { std.set(true, forKey: flag) }
        // 旧域名即未打包时的可执行文件名，真机实测确认（defaults find 出来的就是这个）。
        guard let old = UserDefaults(suiteName: "VibeKitApp") else { return }

        // profiles.v1：合并而非覆盖——旧域里"新域没有的配置名"补进来；同名冲突新域优先
        // （新域是当前 App 正在用的，不能被旧数据覆盖）。
        let profilesKey = "profiles.v1"
        if let oldData = old.data(forKey: profilesKey),
           let oldProfiles = try? JSONDecoder().decode([String: Profile].self, from: oldData) {
            var merged = oldProfiles
            if let newData = std.data(forKey: profilesKey),
               let newProfiles = try? JSONDecoder().decode([String: Profile].self, from: newData) {
                for (name, p) in newProfiles { merged[name] = p }
            }
            if let encoded = try? JSONEncoder().encode(merged) {
                std.set(encoded, forKey: profilesKey)
            }
        }

        // 其余标量键：仅当新域没有该键时才从旧域复制，不覆盖用户已经在新域做过的改动。
        for k in ["activeProfile", "appearance", "dialIdx", "enforceVibeMic", "mediaFunc", "partAdjust",
                  "appBindings.v1", "pendingSentinelClear.v1", AppLanguage.preferenceKey]
            where std.object(forKey: k) == nil {
            if let v = old.object(forKey: k) { std.set(v, forKey: k) }
        }
    }

    // 无条件触发跨域迁移：实例存储属性按声明顺序初始化，放在第一个即保证迁移先于任何配置读取。
    // 不要删这行——迁移的触发原本依赖「某个属性恰好读了 migratedDefaults」这一不成文约定，
    // 后人把那些属性改成 lazy 或挪进 init 方法体，迁移就会静默跳过且不报错。
    private let defaults = VibeVM.migratedDefaults

    @Published var connected = false      // 设备真正在线（能响应命令），非仅连接器在位
    @Published var linkPresent = false    // 连接器（dongle）已插好、HID 会话已打开
    private var offlineStrikes = 0         // 连续读不到电池的次数（≥2 才判离线，防偶发丢帧误判）
    @Published var connecting = false
    @Published var status = "未连接"
    @Published var sn = "—"; @Published var firmware = "—"; @Published var battery = "—"
    @Published var snRX = "—"; @Published var fwRX = "—"   // 接收端(dongle/RX)
    @Published var batteryPercent: Int? = nil
    @Published var charging = false
    @Published var brightness: Double = 0
    @Published var micOn = false
    @Published var currentInput = "—"
    @Published var inputDevices: [AudioInput] = []
    @Published var ledMode = 1
    @Published var ledBrightness = 2   // 档位 0/1/2（灭/低/高）
    // 电源：待机/休眠时长(秒)。设备默认 300 / 3600。
    @Published var standbyTime = 300
    @Published var sleepTime = 3600
    @Published var rebooting = false
    // 调试面板「唤醒」按钮的结果：nil=未试过/正在试，之后是 success/noResponse。
    enum WakeResult { case success, noResponse }
    @Published var waking = false
    @Published var wakeResult: WakeResult? = nil
    @Published var enforceVibeMic = VibeVM.migratedDefaults.bool(forKey: "enforceVibeMic")
    // 锁定目标设备名（修复轮次 2：语义从写死 AU05 改为"锁当前选中设备"）。
    // 向后兼容：旧数据只有 enforceVibeMic(Bool)、没有目标名——若曾经锁定过，回退到 "AU05"，
    // 保证老用户升级后行为不变；从未锁定过则目标名留空。
    @Published var enforceTargetName: String = {
        if let name = VibeVM.migratedDefaults.string(forKey: "enforceTargetName"), !name.isEmpty { return name }
        return VibeVM.migratedDefaults.bool(forKey: "enforceVibeMic") ? "AU05" : ""
    }()
    // 锁定目标设备 uid（真正的匹配依据，见 InputEnforcer）。老数据没有这个键——留空即可，
    // InputEnforcer 会自动退回 enforceTargetName 的子串匹配，首次命中后再回写这里。
    @Published var enforceTargetUID: String = VibeVM.migratedDefaults.string(forKey: "enforceTargetUID") ?? ""
    // 心跳：每次成功轻量读 +1，驱动右上角 "+1" 上浮动画。
    @Published var heartbeat = 0
    // 主题：system / light / dark（记忆到 UserDefaults）。
    @Published var scheme: String = VibeVM.migratedDefaults.string(forKey: "appearance") ?? "system"
    var colorScheme: ColorScheme? { scheme == "light" ? .light : scheme == "dark" ? .dark : nil }

    private let enforcer = InputEnforcer()
    private var hbTimer: Timer?
    @Published var buttons: [ButtonState] = [
        .init(id: "btn1", title: "按钮 1"), .init(id: "btn2", title: "按钮 2"), .init(id: "btn3", title: "按钮 3"),
    ]
    // 旋钮三个动作（复用按键 0x50 快捷键帧，仅 index 不同）。
    @Published var dial: [ButtonState] = [
        .init(id: "dialL", title: "左转"), .init(id: "dialR", title: "右转"), .init(id: "dialP", title: "按下"),
    ]
    // 左转/右转/按下的 0x50 index。真机标定确认(2026-08-31)：左转=5 右转=4 按下=3。可在「标定」里改并持久化。
    @Published var dialIdx: [Int] = {
        if let a = VibeVM.migratedDefaults.array(forKey: "dialIdx") as? [Int], a.count == 3 { return a }
        return [5, 4, 3]
    }()
    // 哪些槽位当前写的是「固定功能」媒体键：slot id(btn1/2/3、dialL/R/P) → funcIndex。
    // 设备的 0x50 读回表达不了固定功能（读到的是被覆盖前的旧快捷键），只能本地记账。
    @Published var mediaFunc: [String: UInt8] = {
        let raw = VibeVM.migratedDefaults.dictionary(forKey: "mediaFunc") as? [String: Int] ?? [:]
        return raw.mapValues { UInt8(max(0, min(255, $0))) }
    }()
    private func persistMediaFunc() {
        defaults.set(mediaFunc.mapValues { Int($0) }, forKey: "mediaFunc")
    }
    // 哪些槽位当前绑的是「打开 App」：slot id → 绑定。
    // 与 mediaFunc 同一类问题——设备的 0x50 读回只会给出哨兵组合键本身，
    // 表达不了「这个槽绑的是 iTerm2」，只能本地记账。
    @Published var appBindings: [String: AppBinding] = {
        guard let d = VibeVM.migratedDefaults.data(forKey: "appBindings.v1"),
              let m = try? JSONDecoder().decode([String: AppBinding].self, from: d) else { return [:] }
        return m
    }()
    private func persistAppBindings() {
        if let d = try? JSONEncoder().encode(appBindings) { defaults.set(d, forKey: "appBindings.v1") }
    }
    /// 「设备上还欠一次哨兵清除」的账（槽位 id 集合）。判定逻辑在 SentinelBookkeeping。
    ///
    /// 哨兵是程序自己烧进设备的，不是用户配的快捷键——所以丢绑定时必须自己销账。
    /// 但丢绑定的那一刻设备常常不在场（离线解绑、切到没配过这个槽的配置），写不进去；
    /// 用户又很可能在设备回来之前就退了 App。不落盘的话，设备上就永远留着一个
    /// 「按下会往前台 App 打一串 ⌃⌥⌘F9」的死键，而界面写着「未设置」。
    /// 持久化方式与 appBindings.v1 同款：UserDefaults，跨域迁移名单里也带上它。
    private var pendingSentinelClear: Set<String> = {
        Set(VibeVM.migratedDefaults.stringArray(forKey: "pendingSentinelClear.v1") ?? [])
    }()
    private func persistPendingSentinelClear() {
        defaults.set(pendingSentinelClear.sorted(), forKey: "pendingSentinelClear.v1")
    }
    /// 记一笔：这个槽的设备侧哨兵还没清掉。
    private func markSentinelPendingClear(_ slot: String) {
        guard APP_BINDABLE_SLOTS.contains(slot) else { return }
        guard pendingSentinelClear.insert(slot).inserted else { return }
        persistPendingSentinelClear()
    }
    /// 槽位状态是否已经**真的加载过**（从存档回填，或首次使用时从设备读回）。
    ///
    /// 存在的理由是 goOnline() 的这个顺序：先 `connected = true`，**之后**才异步
    /// loadDeviceState()（读 SN/固件/亮度/待机/休眠，每项还带重试），读完才 applyProfile
    /// 把 ButtonState 填上。中间这段窗口里 connected 已经为真，而 buttons/dial 还是初始
    /// 空状态（current="读取中…"、tokens=[]）。
    ///
    /// autosave() 的快照直接取 buttons.map(\.tokens)——窗口期内任何一次自动保存
    /// （改麦克风、调灯效、动降噪、改待机时长……）都会把**全空的按键配置**写进活动存档，
    /// 把用户真实的配置覆盖掉。只用 connected 当闸门挡不住这个，必须再加一道水位。
    private var slotsHydrated = false

    /// 哨兵相关的一次性提示（自动换键 / 池耗尽 / App 找不到）。UI 显示后由用户关掉，置 nil。
    @Published var sentinelNotice: LocalizedMessage? = nil

    /// 槽位 id → 0x50 命令的 index。三个按键走固定表，旋钮方向走标定值。
    private func slotIndex(_ id: String) -> UInt8? {
        if let i = VibeKitDevice.keyIndex(id) { return i }
        guard let k = dial.firstIndex(where: { $0.id == id }) else { return nil }
        return UInt8(max(0, min(255, dialIdx[k])))
    }

    /// 按当前记账重刷某个槽的展示状态。
    /// 传 nil 是有意的：绑着 App 时 fillState 第一分支就短路了，读不读回都无所谓；
    /// 解绑后本来就该显示「未设置」。
    private func refreshSlotUI(_ slot: String) {
        mutateSlotState(slot) { fillState(&$0, from: nil) }
    }

    /// 丢掉某槽的 App 绑定并注销其热键。设备侧不动——调用方通常紧接着要写别的东西进去。
    ///
    /// 三个展示字段的复位放在 guard **之前**：本来就是幂等操作（没绑定时全是 nil/false），
    /// 而放在外面就要在四个调用点各抄一遍，漏掉任何一处，行里就会留着一句陈旧的
    /// 「打开 App：iTerm2」——曾经就是这么抄了四份。
    private func dropAppBinding(_ slot: String) {
        mutateSlotState(slot) { $0.appName = nil; $0.sentinelDisplay = nil; $0.appMissing = false; $0.sentinelDead = false }
        guard appBindings[slot] != nil else { return }
        HotKeyCenter.shared.unregister(slot)
        appBindings[slot] = nil
        persistAppBindings()
        // 设备不在线就写不掉那串哨兵，记账等它回来再补——否则界面显示「未设置」，
        // 按下去却往前台 App 打一串 ⌃⌥⌘F9。
        // 判据用 connected 而不是 dev != nil：AU05 关机、连接器还插着时 goOffline 并不会
        // 把 dev 置空，此时写命令照发不误、照样超时失败，dev 非空完全不代表写得进去。
        // 多记一笔无害：drain 会复核槽位现在是否真空着，不空就只销账不写。
        if !connected { markSentinelPendingClear(slot) }
    }

    /// 对某个槽的展示状态做一次原地修改（按键三个 + 旋钮三个，id 唯一）。
    private func mutateSlotState(_ slot: String, _ body: (inout ButtonState) -> Void) {
        if let i = buttons.firstIndex(where: { $0.id == slot }) { body(&buttons[i]) }
        if let i = dial.firstIndex(where: { $0.id == slot }) { body(&dial[i]) }
    }
    /// 某个槽此刻是否确实空着——没绑 App、没媒体键、也没普通快捷键。
    /// 补清哨兵前的复核依据：不空就说明已经被别的东西占住了，再写空会抹掉刚落地的配置。
    private func slotIsVacant(_ slot: String) -> Bool {
        guard appBindings[slot] == nil, mediaFunc[slot] == nil else { return false }
        return slotState(slot)?.tokens.isEmpty ?? true
    }
    /// 按槽位 id 取展示状态（按键三个 + 旋钮三个，id 唯一）。
    private func slotState(_ slot: String) -> ButtonState? {
        buttons.first { $0.id == slot } ?? dial.first { $0.id == slot }
    }
    /// 把欠下的哨兵清除补上。只在设备在场时有意义，故由 applyProfile 调用。
    private func drainPendingSentinelClears() {
        guard connected, let d = dev, !pendingSentinelClear.isEmpty else { return }
        let plan = SentinelBookkeeping.drainPlan(pending: pendingSentinelClear,
                                                 order: APP_BINDABLE_SLOT_ORDER,
                                                 isVacant: { self.slotIsVacant($0) })
        pendingSentinelClear.subtract(plan.settled)
        persistPendingSentinelClear()
        let idxs = plan.clear.compactMap { slotIndex($0) }
        guard !idxs.isEmpty else { return }
        io.async {
            for idx in idxs {
                // tokens: [] 会连 0x10 固定功能一起清——两套存储都得干净
                try? d.setKeyboardShortcut(index: idx, tokens: [])
                Thread.sleep(forTimeInterval: 0.08)   // 同 applyProfile：批量连发固件会丢帧
            }
        }
    }
    @Published var probe: [ProbeRow] = []   // 标定探测结果（index 0..9 当前映射）
    @Published var nrLevel = 0              // 麦克风降噪级别 0..3
    @Published var micUiFlick = false      // 麦克风 UI 闪烁提示
    @Published var indicatorBreathe = false // 指示灯呼吸（全局）
    @Published var ledRaw = ""             // 灯效原始配置 hex（诊断/标定用）
    @Published var ledTypes: [Int] = [2, 0, 0, 1]  // 工作模式各灯 type：[btn1,btn2,btn3,dial] 0灭/1常亮/2呼吸
    @Published var inputVol: Double = 0     // 系统输入音量(增益) 0..1
    @Published var inputVolSupported = false // 当前输入设备是否支持软件调节增益
    // 设备图圆圈的手动对位偏移（点，持久化）。
    @Published var partAdjust: [String: CGSize] = {
        var m: [String: CGSize] = [:]
        if let d = VibeVM.migratedDefaults.dictionary(forKey: "partAdjust") as? [String: [Double]] {
            for (k, v) in d where v.count == 2 { m[k] = CGSize(width: v[0], height: v[1]) }
        }
        return m
    }()
    @Published var calibrating = false      // 对位模式（可拖动圆圈）
    @Published var profileNames: [String] = []   // 本地存档名列表
    @Published var profileUpdated: [String: Date] = [:]  // 每个配置的最近更新时间
    @Published var activeName: String = VibeVM.migratedDefaults.string(forKey: "activeProfile") ?? "默认"  // 当前活动配置（持久化，下次启动默认加载）
    @Published var activeUpdatedAt: Date? = nil   // 活动配置最近更新时间
    @Published var saveTick = 0                   // 每次自动保存 +1，驱动「已保存」提示
    private let profKey = "profiles.v1"

    private let hid = VibeKitHID()
    private var dev: VibeKitDevice?
    private let io = DispatchQueue(label: "com.vibekit.app.io")

    /// 幂等连接：已连上或正在连就不重复发起。供 App 启动时自动调用。
    func connectIfNeeded() {
        guard !connected, !linkPresent, !connecting else { return }
        connect()
    }

    func connect() {
        connecting = true; status = "连接中…"
        let hid = self.hid  // let，非隔离
        io.async {
            do { try hid.open() } catch {
                DispatchQueue.main.async { self.status = "连接失败，请重试"; self.connecting = false; self.linkPresent = false }; return
            }
            let d = VibeKitDevice(hid)
            // 连接器插上 ≠ AU05 已开机：用一次电池读探测设备是否真正在线（未开机时命令超时返回 nil）。
            let bat = retryRead(2) { d.getBatteryFull() }
            DispatchQueue.main.async {
                self.dev = d
                self.connecting = false
                self.linkPresent = true
                self.refreshAudio()
                self.refreshInputVolume()
                self.startEnforceIfNeeded()
                self.startHeartbeat()          // 心跳兼在线探测：设备后开机会被自动检测并加载
                self.applyBatteryReading(bat)  // 在线→goOnline() 读 SN/固件/快捷键；离线→保持等待
                if !self.connected { self.status = "已插好连接器，等待 AU05 开机…" }
            }
        }
    }

    /// 上线时加载配置：**本地存档为准**（VibeKey 那份可能被原厂 App 改过、或掉电丢失）。
    /// 有活动配置 → 回填 UI 并写回设备；没有（首次使用）→ 读设备现状回填并据此建档。
    /// 既用于首次在线，也用于设备「后开机」时的动态加载（问题 3）。
    func loadDeviceState() {
        guard let d = dev else { return }
        let profile = loadProfiles()[activeName]
        let dialIdxs = self.dialIdx.map { UInt8(max(0, min(255, $0))) }
        io.async {
            // 设备身份信息不在配置里，始终读。
            let sn = retryRead(3) { d.getSN() } ?? "—"
            let fw = retryRead(3) { d.getVersion() } ?? "—"
            let br = d.getBrightness() ?? 0
            // 待机/休眠是设备侧全局设置，先读真实值当初值；若配置里存了值，applyProfile 会覆盖并写回设备。
            let sbt = retryRead(2) { d.getStandbyTime() }
            let slt = retryRead(2) { d.getSleepTime() }
            guard profile == nil else {
                DispatchQueue.main.async {
                    self.sn = sn; self.firmware = fw; self.brightness = Double(br)
                    if let sbt { self.standbyTime = sbt }
                    if let slt { self.sleepTime = slt }
                    guard let p = profile else { return }
                    self.activeUpdatedAt = p.updatedAt.map { Date(timeIntervalSince1970: $0) }
                    self.applyProfile(p)   // 回填 UI + 写入设备
                    self.slotsHydrated = true   // 从这一刻起 autosave 的快照才代表真实配置
                }
                return
            }
            // 首次使用：本地无存档，用设备当前状态建档。
            let mic = d.getMicEnable() ?? false
            let nr = d.getMicNRLevel() ?? 0
            let uif = d.getMicUiFlick() ?? false
            let brth = d.getIndicatorBreathe() ?? false
            let ltypes = d.getLedTypes() ?? [2, 0, 0, 1]
            // 用 getSlot 而非只读 0x50：媒体键存在 0x10 里，只读 0x50 会把它漏成「未设置」。
            var reads: [String: [String]?] = [:]
            for id in ["btn1", "btn2", "btn3"] {
                reads[id] = VibeKitDevice.keyIndex(id).flatMap { effectiveTokens(d.getSlot(index: $0)) }
            }
            let dialReads: [[String]?] = dialIdxs.map { effectiveTokens(d.getSlot(index: $0)) }
            DispatchQueue.main.async {
                self.sn = sn; self.firmware = fw
                if let sbt { self.standbyTime = sbt }
                if let slt { self.sleepTime = slt }
                self.brightness = Double(br); self.micOn = mic
                self.nrLevel = nr; self.micUiFlick = uif; self.indicatorBreathe = brth
                self.ledTypes = ltypes.count == 4 ? ltypes : [2, 0, 0, 1]
                for i in self.buttons.indices { self.fillState(&self.buttons[i], from: reads[self.buttons[i].id] ?? nil) }
                for k in self.dial.indices { self.fillState(&self.dial[k], from: k < dialReads.count ? dialReads[k] : nil) }
                self.slotsHydrated = true   // 首次使用：ButtonState 刚从设备读回填好，同样算加载完成
                self.ensureActiveProfile()
                // 这条分支不经过 applyProfile，所以哨兵得自己补写一遍。
                // 真会走到：本地还没建过配置（首次使用）时用户就先离线绑了 App——
                // 那时 writeSentinelToDevice 是空转，设备里从来没有过这串哨兵。
                self.flushBoundSentinelsToDevice()
            }
        }
    }

    // 电池读结果驱动 在线/离线 转换（连续两次读不到才判离线，避免偶发丢帧误判）。
    private func applyBatteryReading(_ bat: (percent: Int, voltage: Int, charging: Bool)?) {
        if let bat {
            offlineStrikes = 0
            battery = "\(bat.percent)%  \(String(format: "%.2f", Double(bat.voltage)/1000))V"
            batteryPercent = bat.percent; charging = bat.charging
            heartbeat &+= 1
            if !connected { goOnline() }
        } else {
            offlineStrikes += 1
            guard offlineStrikes >= 2 else { return }
            // 连续读不到有两种完全不同的处境，必须分开处置，否则界面会停在错误的状态上：
            //   · 接收器还在 → 设备待机或关机。保持 linkPresent，等待卡上的「尝试唤醒」有意义。
            //   · 接收器被拔 → 手里的 HID 会话已经死了。`dev` 引用不会自己变 nil、isOpen 照样
            //     为真，光看命令失败分不出是哪种，所以直接问 IOKit。
            //
            // 早先没有这道区分：拔掉接收器后 linkPresent 永远保持 true（它只在 connect 失败
            // 那条路径上被置 false），dev 也永不置空。结果是界面卡在「AU05 没有响应」那张等待
            // 卡上，切不到带「连接设备」的未连接卡；而卡上两个按钮都通过了 `guard let dev`，
            // 实际在对一个死掉的会话发命令，必然失败——按下去和坏了一模一样。
            if !VibeKitHID.devicePresent() { teardownLink(); return }
            if connected { goOffline() }
        }
    }
    // 离线→在线：读取并加载全部设备信息。
    private func goOnline() {
        connected = true; status = "已连接 VibeKey"
        loadDeviceState()
    }
    /// 接收器被拔：整个 HID 会话作废，退回「未连接」。
    ///
    /// 与 goOffline() 的分工——goOffline 是「设备不在线但链路还在」，teardownLink 是「链路没了」。
    /// 心跳定时器**故意不停**：dev 为 nil 后 beat() 会转为定期探测接收器是否插回来，
    /// 插回去就自动重连，用户不必手点。
    private func teardownLink() {
        hid.close()
        dev = nil
        if connected { goOffline() }
        linkPresent = false
        connected = false
        offlineStrikes = 0
        status = "连接器已拔出"
    }

    // 在线→离线：AU05 关机但连接器仍在，清掉过期信息、退回等待态。
    private func goOffline() {
        // 水位跟着掉：下次上线又会经历一段「connected 为真但状态没填」的窗口
        slotsHydrated = false
        connected = false; status = "AU05 未开机（连接器仍在）"
        battery = "—"; batteryPercent = nil; charging = false
        sn = "—"; firmware = "—"
    }

    // 从读回 tokens 回填一个动作状态（按键/旋钮通用）。
    //
    // 优先级必须是「打开 App > 媒体键 > 读回 tokens」，两条本地记账都排在读回之前：
    // 设备里存的是哨兵组合键，0x50 读回只会得到 ⌃+⌥+⌘+F9，表达不了「这个槽绑的是 iTerm2」；
    // 媒体键更甚，读回的是被覆盖前的旧快捷键。漏了这两条，表现是「绑好后重新连接设备，
    // 界面变回显示一串组合键」——功能其实还在，但用户会以为配置丢了。
    func fillState(_ s: inout ButtonState, from tk: [String]?) {
        // 必须过一遍 APP_BINDABLE_SLOTS：只有 btn1/2/3/dialP 会被哨兵注册循环照顾到。
        // 一条越界的 appBindings["dialL"]（老数据、手改 defaults、将来某处写错槽位）
        // 若照样渲染，就会永远显示成一个「工作正常」的绑定，而实际上从没人给它注册热键。
        if APP_BINDABLE_SLOTS.contains(s.id), let ab = appBindings[s.id] {
            s.mods = Set(ab.sentinelTokens.filter { VibeKitKeymap.isModifierToken($0) })
            s.mainKey = ab.sentinelTokens.first { !VibeKitKeymap.isModifierToken($0) }
            s.appName = ab.displayName
            s.sentinelDisplay = ab.sentinelDisplay
            s.current = "打开 App：\(ab.displayName)"
            // 死活由「热键此刻注册着没有」直接推出，不另存一份状态——HotKeyCenter 就是唯一真相。
            // 注意调用时机：applyProfile 里 fillState 跑在重注册**之前**，那一轮的取值可能是旧的，
            // 所以重注册收尾时会把四个可绑槽位统统 refreshSlotUI 一遍。
            s.sentinelDead = !HotKeyCenter.shared.isRegistered(s.id)
            return
        }
        s.appName = nil; s.sentinelDisplay = nil; s.appMissing = false; s.sentinelDead = false
        // 固定功能槽次之：设备读回的是被覆盖前的旧 0x50 快捷键，不代表当前实际行为。
        if let f = mediaFunc[s.id], let label = mediaLabel(f) {
            s.mods = []; s.mainKey = mediaToken(f); s.current = label; return
        }
        if let tk, !tk.isEmpty {
            s.mods = Set(tk.filter { VibeKitKeymap.isModifierToken($0) })
            s.mainKey = tk.first { !VibeKitKeymap.isModifierToken($0) }
            s.current = VibeKitKeymap.tokensToDisplay(tk)
        } else { s.mods = []; s.mainKey = nil; s.current = "未设置" }
    }

    // MARK: 旋钮动作（复用 setShortcut/getShortcut，index = dialIdx）
    func applyDial(_ i: Int) {
        guard let d = dev else { return }
        let idx = UInt8(max(0, min(255, dialIdx[i])))
        dropAppBinding(dial[i].id)   // 三者互斥（展示字段的复位在 dropAppBinding 里）
        if let f = mediaFuncIndex(dial[i].mainKey) {
            // 媒体键：setMediaKey 内部会先清 0x50 再写 0x10（0x50 非空会压制 0x10）。无法读回，直接置显示。
            mediaFunc[dial[i].id] = f; persistMediaFunc()
            dial[i].mods = []; dial[i].current = mediaLabel(f) ?? "媒体键"
            io.async { try? d.setMediaKey(index: idx, funcIndex: f) }
        } else {
            // 普通键/组合键：setKeyboardShortcut 内部先把 0x10 清 0 再写 0x50，两套存储不能同时有值。
            mediaFunc[dial[i].id] = nil; persistMediaFunc()
            let tokens = dial[i].tokens
            io.async {
                try? d.setKeyboardShortcut(index: idx, tokens: tokens)
                let rb = d.getShortcut(index: idx)
                DispatchQueue.main.async { self.fillState(&self.dial[i], from: rb) }
            }
        }
        autosave()
    }
    func clearDial(_ i: Int) {
        guard let d = dev else { return }
        let idx = UInt8(max(0, min(255, dialIdx[i])))
        dropAppBinding(dial[i].id)
        mediaFunc[dial[i].id] = nil; persistMediaFunc()
        io.async { try? d.setKeyboardShortcut(index: idx, tokens: [])
            DispatchQueue.main.async { self.fillState(&self.dial[i], from: []) } }
        autosave()
    }
    // 只读探测 index 0..9 的当前映射（标定用，无副作用）。
    func runProbe() {
        guard let d = dev else { return }
        io.async {
            var rows: [ProbeRow] = []
            for idx in 0...9 {
                let tk = d.getShortcut(index: UInt8(idx))
                let disp: String
                if let tk { disp = tk.isEmpty ? "（空槽）" : VibeKitKeymap.tokensToDisplay(tk) } else { disp = "无响应" }
                rows.append(ProbeRow(id: idx, disp: LocalizedMessage(disp)))
            }
            DispatchQueue.main.async { self.probe = rows }
        }
    }
    // 旋钮标定：给 index 3…9 各写入对应「数字键」(3→"3" … 9→"9")，彼此可区分。
    // 用户在文本框里转动/按下旋钮，冒出哪个数字即知该动作对应哪个 index。不动 0/1/2(物理按键)。
    func writeDialMarkers() {
        guard let d = dev else { return }
        io.async {
            for i in 3...9 { try? d.setShortcut(index: UInt8(i), tokens: [String(i)]) }
            DispatchQueue.main.async { self.probe = (3...9).map { ProbeRow(id: $0, disp: LocalizedMessage("已标记为数字键 {0}", String($0))) } }
        }
    }
    // 调整某方向的 index 并重新读回其当前映射。
    func setDialIndex(_ i: Int, _ v: Int) {
        dialIdx[i] = max(0, min(15, v))
        defaults.set(dialIdx, forKey: "dialIdx")
        guard let d = dev else { return }
        let idx = UInt8(dialIdx[i])
        io.async { let rb = d.getShortcut(index: idx)
            DispatchQueue.main.async { self.fillState(&self.dial[i], from: rb) } }
    }

    // 心跳：连接后每 3s 后台读一次电量，成功即 +1 并刷新电量。
    func startHeartbeat() {
        hbTimer?.invalidate()
        let t = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.beat() }
        }
        RunLoop.main.add(t, forMode: .common)
        hbTimer = t
    }
    func beat() {
        guard let d = dev else {
            // 会话已被 teardownLink 拆掉（接收器拔出）。这条心跳转岗当重连探测：
            // 只在接收器确实插回来时才发起 connect()，否则每 3 秒就会把 status 刷成
            // 「连接失败，请重试」，把一个正常的等待态渲染得像故障。
            if !linkPresent, !connecting, VibeKitHID.devicePresent() { connect() }
            return
        }
        io.async {
            let bat = retryRead(2) { d.getBatteryFull() }
            DispatchQueue.main.async { self.applyBatteryReading(bat) }
        }
    }

    func applyShortcut(_ i: Int) {
        guard let d = dev, let idx = VibeKitDevice.keyIndex(buttons[i].id) else { return }
        dropAppBinding(buttons[i].id)   // 三者互斥：改成快捷键/媒体键就不再是「打开 App」
        if let f = mediaFuncIndex(buttons[i].mainKey) {
            // 媒体键：setMediaKey 先清 0x50 再写 0x10。无法读回，直接置显示。
            mediaFunc[buttons[i].id] = f; persistMediaFunc()
            buttons[i].mods = []; buttons[i].current = mediaLabel(f) ?? "媒体键"
            io.async { try? d.setMediaKey(index: idx, funcIndex: f) }
            autosave(); return
        }
        // 普通键/组合键：setKeyboardShortcut 内部先把 0x10 清 0 再写 0x50。
        mediaFunc[buttons[i].id] = nil; persistMediaFunc()
        let tokens = buttons[i].tokens
        io.async {
            try? d.setKeyboardShortcut(index: idx, tokens: tokens)
            let rb = d.getShortcut(index: idx)
            DispatchQueue.main.async {
                if let rb, !rb.isEmpty {
                    // 回读权威回填：开关/主键与设备实际存储一致（修正 ⌃ 等未同步显示）。
                    self.buttons[i].mods = Set(rb.filter { VibeKitKeymap.isModifierToken($0) })
                    self.buttons[i].mainKey = rb.first { !VibeKitKeymap.isModifierToken($0) }
                    self.buttons[i].current = VibeKitKeymap.tokensToDisplay(rb)
                } else { self.buttons[i].current = "未设置" }
            }
        }
        autosave()
    }

    func refreshAudio() {
        currentInput = VibeKitAudio.currentInputName()
        inputDevices = VibeKitAudio.inputDevices()
    }
    func setInput(_ id: AudioDeviceID) {
        DispatchQueue.global().async { _ = VibeKitAudio.setDefaultInput(id)
            DispatchQueue.main.async { self.refreshAudio(); self.refreshInputVolume() } }
    }
    // 麦克风降噪级别（写设备）。
    func applyNR() { guard let d = dev else { return }; let l = nrLevel; io.async { try? d.setMicNRLevel(l) }; autosave() }
    // 麦克风 UI 闪烁提示（关掉可让 btn1 灯不再闪）。
    func applyMicUiFlick() { guard let d = dev else { return }; let on = micUiFlick; io.async { try? d.setMicUiFlick(on) }; autosave() }
    // 指示灯呼吸（全局）。
    func applyIndicatorBreathe() { guard let d = dev else { return }; let on = indicatorBreathe; io.async { try? d.setIndicatorBreathe(on) }; autosave() }
    // 工作模式单灯 type（0灭/1常亮/2呼吸）。i: 0=btn1 1=btn2 2=btn3 3=dial。
    // 一次带上全部 4 灯当前值，避免改一个把其它灯清掉。
    func applyLedType(_ i: Int) {
        guard let d = dev, i < ledTypes.count else { return }
        let types = ledTypes
        io.async { try? d.setLedTypes(types, focus: i) }
        autosave()
    }
    // 诊断：读回灯效原始配置 hex（若关呼吸仍呼吸，据此定位 btn1 的 per-LED 块）。
    func readLedRaw() {
        guard let d = dev else { return }
        io.async {
            let raw = d.getIndicatorRaw() ?? []
            let hex = raw.map { String(format: "%02x", $0) }.joined(separator: " ")
            DispatchQueue.main.async { self.ledRaw = hex.isEmpty ? "无响应" : hex }
        }
    }
    // 系统输入音量(增益)：读/写当前默认输入设备。
    func refreshInputVolume() {
        if let id = VibeKitAudio.defaultInputID(), let v = VibeKitAudio.inputVolume(id) {
            inputVol = Double(v); inputVolSupported = true
        } else { inputVolSupported = false }
    }
    func applyInputVol() {
        guard let id = VibeKitAudio.defaultInputID() else { return }
        let v = Float(inputVol)
        DispatchQueue.global().async {
            VibeKitAudio.setInputVolume(id, v)
            DispatchQueue.main.async { self.refreshInputVolume() }  // 回读实际值：不支持则滑块弹回
        }
    }
    // 设备图圆圈手动对位偏移的持久化。
    func setAdjust(_ id: String, _ s: CGSize) {
        partAdjust[id] = s
        var d: [String: [Double]] = [:]
        for (k, v) in partAdjust { d[k] = [Double(v.width), Double(v.height)] }
        defaults.set(d, forKey: "partAdjust")
    }

    // MARK: 本地配置存档（Profile）
    init() {
        // 名字回落匹配命中时，enforcer 会把解析出的真实 uid 回调回来——存下来，下次启动就能走
        // uid 精确匹配，不用再依赖子串匹配。回调可能在任意队列触发，切回主线程再碰 @Published/UserDefaults。
        enforcer.onResolvedUID = { [weak self] uid in
            Task { @MainActor [weak self] in
                guard let self, self.enforceTargetUID != uid else { return }
                self.enforceTargetUID = uid
                self.defaults.set(uid, forKey: "enforceTargetUID")
            }
        }
        let all = loadProfiles()
        publishMeta(all)
        activeUpdatedAt = all[activeName]?.updatedAt.map { Date(timeIntervalSince1970: $0) }
        // 启动自动连接的真正触发点。之前挂在 MenuBarExtra 的 content 闭包（MiniPanel）的 .task
        // 上，代码评审通过实际运行验证：MenuBarExtra(.menuBarExtraStyle(.window)) 的 content
        // 是懒加载的，只有 label 图标随 App 启动就渲染，content 视图要等用户第一次点开顶栏图标
        // 才会被构建，.task 才会跟着跑——结果是「常驻了但要点一下才开始连」，不是启动即连。
        // 这里改用 VibeVM.init：vm 是 App 层的 @StateObject，SwiftUI 构建 body 前就必须先造出
        // 这个实例，所以 init 一定随 App 启动执行，不依赖任何界面是否被渲染过。
        Task { @MainActor [weak self] in
            // 先注册哨兵热键再连设备：热键不依赖设备在线，用户按下时该跳就跳。
            // 这里**只还原存档里的组合**，不换键：此刻 dev 还是 nil，换出来的新组合写不进设备，
            // 界面却会一口咬定「已自动更换为 ⌃⌥⌘F10」而设备还在发 F9。
            // 存档组合注册不上的槽就是死的，如实标 sentinelDead；换键留给设备在场的 applyProfile。
            self?.registerStoredSentinels()
            self?.connectIfNeeded()
        }
    }
    private func loadProfiles() -> [String: Profile] {
        guard let data = defaults.data(forKey: profKey),
              let m = try? JSONDecoder().decode([String: Profile].self, from: data) else { return [:] }
        return m
    }
    private func persistProfiles(_ m: [String: Profile]) {
        if let data = try? JSONEncoder().encode(m) { defaults.set(data, forKey: profKey) }
        publishMeta(m)
    }
    // 发布配置列表名 + 各自的最近更新时间（供弹层分别显示）。
    private func publishMeta(_ m: [String: Profile]) {
        profileNames = m.keys.sorted()
        var upd: [String: Date] = [:]
        for (k, v) in m { if let t = v.updatedAt { upd[k] = Date(timeIntervalSince1970: t) } }
        profileUpdated = upd
    }
    private func snapshot(_ at: Double) -> Profile {
        // 绑了 App 的槽，存档里那份 tokens 镜像也写规范顺序的 sentinelTokens：
        // ButtonState.tokens 会按 UI 的 MODS 顺序重排，同一个哨兵在同一份存档里就有了
        // 两种字节序。读取侧（applyProfile）已经一律以 appBindings 为准，这里只是让
        // 存档自身不自相矛盾——两处能各自漂移，本身就是缺陷。
        func mirror(_ s: ButtonState) -> [String] { sentinelMirror(s.id) ?? s.tokens }
        return Profile(buttons: buttons.map(mirror), dial: dial.map(mirror),
                ledMode: ledMode, ledBrightness: ledBrightness, nrLevel: nrLevel,
                micOn: micOn, micUiFlick: micUiFlick, indicatorBreathe: indicatorBreathe,
                ledTypes: ledTypes, standbyTime: standbyTime, sleepTime: sleepTime, updatedAt: at,
                appBindings: appBindings.isEmpty ? nil : appBindings)
    }
    private func setActive(_ name: String) {
        activeName = name
        defaults.set(name, forKey: "activeProfile")
    }
    /// 自动保存当前状态到活动配置（每次改动调用）。
    func autosave() {
        // slotsHydrated 不能省：connected 为真不代表 ButtonState 已经填好，
        // 详见该属性的注释。少存一次无非丢掉一次自动保存，存错一次会抹掉整份按键配置。
        guard connected, slotsHydrated else { return }
        let now = Date()
        var all = loadProfiles(); all[activeName] = snapshot(now.timeIntervalSince1970); persistProfiles(all)
        activeUpdatedAt = now; saveTick &+= 1
    }
    /// 把「打开 App」绑定单独落进活动配置——设备不在线时也必须落。
    ///
    /// 为什么不能直接调 autosave()：它 `guard connected` 是有道理的，设备还没读回来之前
    /// buttons/dial 全是空的，整份快照存下去会把用户配好的快捷键抹成空。
    /// 但绑定/解绑是纯主机侧动作，热键马上就生效了，跟设备在不在线毫无关系。
    /// 早先离线绑定只写了 appBindings.v1、没写进配置，等设备连上 applyProfile 一跑，
    /// appBindings 被那份陈旧配置整个覆盖回去——刚绑的 App 凭空消失。
    /// 这里只动 appBindings 这一个字段，其余原样保留，离线也安全。
    private func saveAppBindingsToProfile(slots: [String]) {
        // 必须连 slotsHydrated 一起判：只看 connected 的话，窗口期内会走进 autosave，
        // 而加闸后的 autosave 直接返回——绑定就只留在 appBindings.v1 里、没进存档。
        // 未到水位时退回下面那条「只改指定槽」的路，它不依赖 ButtonState 是否填好。
        if connected, slotsHydrated { autosave(); return }
        var all = loadProfiles()
        // 配置还没建过（首次使用、设备从未连上）：不在这里凭空造一份空配置——
        // 那会把一堆默认值当成用户配置写进设备。绑定留在 appBindings.v1 里，
        // 等 ensureActiveProfile 用真实设备状态建档时，snapshot 自然会把它带上。
        guard var p = all[activeName] else { return }
        let now = Date()
        p.appBindings = appBindings.isEmpty ? nil : appBindings
        // 存档里 buttons/dial 那份 tokens 镜像也得跟着改——**只改动过的那几个槽**。
        // 漏了它，离线解绑之后存档里仍留着一串哨兵 tokens，设备一连上 applyProfile
        // 就把它当成用户配的普通快捷键回填 + 写回设备，解绑等于白解。
        // 而整份同步是不行的：离线时其余槽的 ButtonState 还是空的（设备没读回来过），
        // 会把用户配好的快捷键抹成空——那正是 autosave 要 guard connected 的原因。
        for slot in slots {
            let tk = sentinelMirror(slot) ?? []
            if let i = buttons.firstIndex(where: { $0.id == slot }), i < p.buttons.count { p.buttons[i] = tk }
            if let i = dial.firstIndex(where: { $0.id == slot }), i < p.dial.count { p.dial[i] = tk }
        }
        p.updatedAt = now.timeIntervalSince1970
        all[activeName] = p
        persistProfiles(all)
        activeUpdatedAt = now; saveTick &+= 1
    }
    /// 该槽在存档 tokens 镜像里应当写什么——绑了 App 就写规范顺序的哨兵，否则 nil（由调用方定夺）。
    private func sentinelMirror(_ slot: String) -> [String]? {
        guard APP_BINDABLE_SLOTS.contains(slot) else { return nil }
        return appBindings[slot]?.sentinelTokens
    }
    /// 连接后确保活动配置存在（无则用当前设备状态建一个；默认名「默认」）。
    func ensureActiveProfile() {
        var all = loadProfiles()
        if let p = all[activeName] {
            activeUpdatedAt = p.updatedAt.map { Date(timeIntervalSince1970: $0) }
        } else {
            let now = Date(); all[activeName] = snapshot(now.timeIntervalSince1970); persistProfiles(all)
            activeUpdatedAt = now
        }
    }
    /// 新增一个配置（用当前状态），并切为活动。
    func addProfile(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !n.isEmpty else { return }
        let now = Date()
        var all = loadProfiles(); all[n] = snapshot(now.timeIntervalSince1970); persistProfiles(all)
        setActive(n); activeUpdatedAt = now; saveTick &+= 1
    }
    func deleteProfile(_ name: String) {
        var all = loadProfiles(); all[name] = nil; persistProfiles(all)
        guard activeName == name else { return }
        // 删掉的是当前活动配置，必须把接任的那份**真正加载一遍**（回填 UI + appBindings +
        // 重注册热键 + 写设备）。早先只是把 activeName 一指、再 ensureActiveProfile 就完事，
        // 于是 UI、appBindings、已注册的热键全都还停在被删那份上；接着任何一次 autosave
        // 都会拿这堆旧状态覆盖掉接任的配置——删一份等于毁两份。
        let next = all.keys.sorted().first ?? "默认"
        if all[next] != nil {
            loadProfile(next)
        } else {
            // 一份都不剩了：没有可加载的东西，退回「用当前设备状态建档」。
            setActive(next); ensureActiveProfile()
        }
    }
    /// 切换/加载某配置：设为活动 + 回填 UI + 写入设备。
    func loadProfile(_ name: String) {
        guard let p = loadProfiles()[name] else { return }
        setActive(name)
        activeUpdatedAt = p.updatedAt.map { Date(timeIntervalSince1970: $0) }
        applyProfile(p)
    }

    /// 把一份配置落地：回填 UI + 写入设备。连接时（本地为准）与手动切换配置共用。
    private func applyProfile(_ p: Profile) {
        // 「打开 App」绑定直接来自存档——tokens 里只有哨兵组合键，反推不出绑的是哪个 App。
        // 老存档没有这个字段（Optional，Swift 合成的 Codable 会给 nil），退化成「一个都没绑」。
        let previousBindings = appBindings
        appBindings = p.appBindings ?? [:]
        persistAppBindings()
        // 切配置会让某些槽「丢掉 App 绑定」——比如配置 A 把 btn1 绑了 iTerm2，配置 B 压根
        // 没配过 btn1。此时热键会被注销，但设备里那串 ⌃⌥⌘F9 还烧着，而 writeSlot 对空槽
        // 是跳过不写的（那条规则本身对：applyProfile 不该替用户清设备）。结果就是按 btn1
        // 往前台 App 打一串 ⌃⌥⌘F9，行里却写着「未设置」。
        // 哨兵不是用户配的东西，是程序自己烧进去的，所以这笔账必须程序自己销。
        // 这里只管记账；新配置有没有往这个槽写别的东西，留给 drain 时复核。
        for slot in SentinelBookkeeping.slotsLosingBinding(previous: previousBindings, next: appBindings,
                                                           order: APP_BINDABLE_SLOT_ORDER) {
            markSentinelPendingClear(slot)
        }
        // 再从配置的 tokens 恢复固定功能记账，fillState 才能把媒体键槽显示正确。
        var mf: [String: UInt8] = [:]
        for (i, tk) in p.buttons.enumerated() where i < 3 {
            let slot = "btn\(i + 1)"
            guard appBindings[slot] == nil else { continue }   // 三者互斥，App 优先
            if let f = tk.compactMap({ mediaFuncIndex($0) }).first { mf[slot] = f }
        }
        for (i, tk) in p.dial.enumerated() where i < dial.count {
            guard appBindings[dial[i].id] == nil else { continue }
            if let f = tk.compactMap({ mediaFuncIndex($0) }).first { mf[dial[i].id] = f }
        }
        mediaFunc = mf; persistMediaFunc()
        // 回填 UI 状态
        for i in buttons.indices where i < p.buttons.count { fillState(&buttons[i], from: p.buttons[i]) }
        for i in dial.indices where i < p.dial.count { fillState(&dial[i], from: p.dial[i]) }
        ledMode = p.ledMode; ledBrightness = p.ledBrightness; nrLevel = p.nrLevel; micOn = p.micOn
        micUiFlick = p.micUiFlick ?? micUiFlick
        indicatorBreathe = p.indicatorBreathe ?? indicatorBreathe
        if let lt = p.ledTypes, lt.count == 4 { ledTypes = lt }
        standbyTime = p.standbyTime ?? standbyTime
        sleepTime = p.sleepTime ?? sleepTime
        // 写入设备（离线生效）
        // 用 if let 而非 guard-return：末尾的哨兵重注册在设备离线时也必须跑到。
        if let d = dev {
        // 绑了 App 的槽一律以 appBindings 里的 sentinelTokens 为准，不用 p.buttons/p.dial
        // 里那份镜像：ButtonState.tokens 会按 UI 的 MODS 顺序重排成 [LCmd,LOpt,LCtrl,F9]，
        // 而 bindApp 写进设备的是 SentinelPool.modifiers 顺序 [LCtrl,LOpt,LCmd,F9]。
        // 同一个逻辑组合两套字节序列，且只有后者在 Oracle 里被逐字节钉死。一份真相：sentinelTokens。
        func writeTokens(_ slot: String, _ mirrored: [String]) -> [String] {
            appBindings[slot]?.sentinelTokens ?? mirrored
        }
        let bt = (0..<3).map { writeTokens("btn\($0 + 1)", p.buttons[safe: $0] ?? []) }
        let dt = dial.indices.map { writeTokens(dial[$0].id, p.dial[safe: $0] ?? []) }
        let idxs = dialIdx.map { UInt8(max(0, min(255, $0))) }
        let lm = p.ledMode, lb = p.ledBrightness, nr = p.nrLevel, mic = p.micOn
        let uif = micUiFlick, brth = indicatorBreathe, lts = ledTypes
        let sbt = standbyTime, slt = sleepTime
        io.async {
            // 一个槽怎么写：
            //   媒体键   → setMediaKey（内部先清 0x50，否则 0x50 会压制 0x10，媒体键不响）
            //   普通组合键 → setKeyboardShortcut（内部先清 0x10）
            //   空槽     → 跳过不写。applyProfile 的职责是应用用户配过的东西，不是替用户清设备；
            //              清除只在用户显式点「清除」时发生（clearShortcut / clearDial）。
            //              早先这里无条件把每个槽都写一遍，把没配过的槽也覆盖掉了。
            // 写之前先读，一样就跳过；写之后回读复核。
            //
            // 这条路不是「偶尔跑一次」：每次「离线→在线」都整份重写，而离线→在线包括
            // **每次待机唤醒**（默认 300 秒待机）和每次拔插接收器。配置一个字节没改也要
            // 重发 21 帧（6 槽 ×2 + 9 项全局），而这个固件对批量连发是**已知会丢帧**的
            // ——下面那两处 sleep 就是为它加的。读一次比写两帧轻，也把丢帧的暴露面砍掉。
            //
            // 回读复核则是补上这条路一直缺的那道校验：用户在界面上手改单个槽走
            // applyShortcut，那条路一直有「回读权威回填」；唯独这条连接时自动重写的批量路
            // 是 try? 写完就算——异常吞掉、不复核。真丢了帧没有任何人会知道，界面继续显示
            // 用户以为的配置。2026-09-05 排查 dongle 转发卡死时，正是因为没有这道校验，
            // 才没法第一步就分清「没写进去」和「写进去了但转发卡死」。
            var mismatched: [String] = []
            func writeSlot(_ label: String, _ index: UInt8, _ tokens: [String]) {
                guard !tokens.isEmpty else { return }
                let wantMedia = tokens.compactMap({ mediaFuncIndex($0) }).first
                if let f = wantMedia {
                    // 媒体键生效的前提是 0x50 空（非空会压制 0x10），两个条件都对上才算一致
                    if d.getButtonFixedFunction(index: index) == f,
                       d.getShortcut(index: index)?.isEmpty ?? false { return }
                    try? d.setMediaKey(index: index, funcIndex: f)
                } else {
                    if d.getShortcut(index: index) == tokens { return }
                    try? d.setKeyboardShortcut(index: index, tokens: tokens)
                }
                Thread.sleep(forTimeInterval: 0.08)   // 逐槽之间留间隔，批量连发固件会丢帧
                let ok = wantMedia.map { d.getButtonFixedFunction(index: index) == $0 }
                    ?? (d.getShortcut(index: index) == tokens)
                if !ok { mismatched.append(label) }
            }
            for i in 0..<min(3, bt.count) {
                guard let idx = VibeKitDevice.keyIndex("btn\(i + 1)") else { continue }
                writeSlot("按钮 \(i + 1)", idx, bt[i])
            }
            let dialLabels = ["旋钮左转", "旋钮右转", "旋钮按下"]
            for i in 0..<min(idxs.count, dt.count) {
                writeSlot(dialLabels[safe: i] ?? "旋钮 \(i)", idxs[i], dt[i])
            }
            // 全局设置逐条之间留点间隔——批量无节流发送时固件会丢帧。
            for send in [{ try? d.setLedMode(lm) }, { try? d.setLedBrightness(lb) }, { try? d.setMicNRLevel(nr) },
                         { try? d.setMicEnable(mic) }, { try? d.setMicUiFlick(uif) }, { try? d.setIndicatorBreathe(brth) },
                         { if lts.count == 4 { try? d.setLedTypes(lts, focus: 0) } },
                         { try? d.setStandbyTime(sbt) }, { try? d.setSleepTime(slt) }] {
                send(); Thread.sleep(forTimeInterval: 0.08)
            }
            // 回读对不上的如实告诉用户。沉默地让界面和设备各说各话是这条路的老毛病。
            if !mismatched.isEmpty {
                let list = mismatched.joined(separator: "、")
                DispatchQueue.main.async { [weak self] in
                    self?.sentinelNotice = LocalizedMessage("这些按键没能写进设备：{0}。", list)
                        + LocalizedMessage("多半是固件丢帧或接收器转发异常——重新插拔接收器，或在界面上改一下该键即可重试。")
                }
            }
        }
        }
        // 补清欠下的哨兵。放在槽位写入之后：io 队列串行，先写配置、再清那些配置没管的槽，
        // 顺序确定；drain 内部还会逐槽复核「现在真的空着吗」，不会抹掉刚写进去的东西。
        drainPendingSentinelClears()
        // 哨兵热键：按恢复后的绑定重注册，必要时换键并重写设备。放在最后——io 队列是串行的，
        // 万一这里换了键，它的重写会排在上面那批槽位写入之后，不会被旧值盖掉。
        //
        // 「换键」只在这里做，不在 init 里做（见 registerStoredSentinels 的注释）：
        // 换键必须连着把新组合写进设备，而设备只有到了这里才可能在场。
        reregisterSentinels()
    }
    func clearShortcut(_ i: Int) {
        guard let d = dev, let idx = VibeKitDevice.keyIndex(buttons[i].id) else { return }
        dropAppBinding(buttons[i].id)
        mediaFunc[buttons[i].id] = nil; persistMediaFunc()
        // setKeyboardShortcut(tokens: []) 会连 0x10 固定功能一起清 —— 两套存储都得清干净。
        io.async { try? d.setKeyboardShortcut(index: idx, tokens: [])
            DispatchQueue.main.async { self.buttons[i].mods = []; self.buttons[i].mainKey = nil; self.buttons[i].current = "未设置" } }
        autosave()
    }

    // MARK: 「打开 App」绑定
    //
    // 机制：给槽位烧一个罕见组合键（哨兵），主机注册同样组合的全局热键去截获。
    // 设备照常离线发出这个组合键——这正是它唯一能表达「按钮被按了」的方式。
    // 退出 Open VibeKey 后没人拦这串组合，理论上它会落到前台 App；但实测没能证实
    // （⌃⌥⌘F9 在 Terminal + cat -v 下什么都没出现），项目按「不漏」处理，界面不再声明该风险。

    /// 给某槽绑定「打开 App」。返回 false = 哨兵池耗尽（已写 sentinelNotice）。
    @discardableResult
    func bindApp(slot: String, bundleID: String, displayName: String) -> Bool {
        guard APP_BINDABLE_SLOTS.contains(slot), let idx = slotIndex(slot) else { return false }
        // 不在这里提前 unregister(slot)：taken 本就排除了本槽自己，
        // HotKeyCenter.register 对同 id 有「新组合先注册成功、再释放旧的」的安全换绑语义，
        // 分配失败时旧注册原样保留——提前拆掉反而会在池耗尽时把「还在正常工作的哨兵」拆没。
        let taken = Set(appBindings.filter { $0.key != slot }.values.compactMap(\.sentinelMainKey))
        guard let combo = SentinelPool.allocate(taken: taken, isRegistrable: { registerSentinel(slot: slot, combo: $0) }) else {
            // 池里 14 个组合一个都分配不出来（4 个可绑槽位远用不完，走到这里基本等于本进程内部出了问题）
            sentinelNotice = LocalizedMessage("哨兵键已用尽——池里 14 个组合都注册不上，暂时无法绑定「{0}」。", displayName)
            refreshSlotUI(slot)
            return false
        }
        appBindings[slot] = AppBinding(bundleID: bundleID, displayName: displayName, sentinelTokens: combo.tokens)
        persistAppBindings()
        mediaFunc[slot] = nil; persistMediaFunc()   // 三者互斥
        writeSentinelToDevice(index: idx, tokens: combo.tokens)
        refreshSlotUI(slot)
        // 不能用 autosave()——它离线时会跳过，绑定就只留在 appBindings.v1 里，
        // 等设备连上 applyProfile 从陈旧配置里恢复，刚绑的 App 凭空消失。
        saveAppBindingsToProfile(slots: [slot])
        return true
    }

    /// 解绑：注销热键 + 清本地记账 + 清空设备该槽。
    func unbindApp(slot: String) {
        guard appBindings[slot] != nil else { return }
        dropAppBinding(slot)
        if let d = dev, let idx = slotIndex(slot) {
            // setKeyboardShortcut(tokens: []) 会连 0x10 固定功能一起清 —— 两套存储都得清干净
            io.async { try? d.setKeyboardShortcut(index: idx, tokens: []) }
        }
        // 设备不在场时清不掉——dropAppBinding 已经把这一笔记进 pendingSentinelClear，
        // 等设备回来由 applyProfile 里的 drain 补上。
        refreshSlotUI(slot)
        saveAppBindingsToProfile(slots: [slot])
    }

    /// 「打开 App」绑定的一览行。给**离线**时的那个区块用——设置界面的快捷键卡整块只在
    /// vm.connected 时渲染，可热键的生命周期跟的是进程、不是设备：设备离线时那几个
    /// ⌃⌥⌘F9 照样被本进程全局吃掉，用户却连看一眼、解个绑都做不到，只能退出 App。
    struct AppBindingRow: Identifiable {
        let id: String          // 槽位 id
        let title: String       // 「按钮 1」「旋钮 · 按下」
        let appName: String
        let sentinel: String    // "⌃⌥⌘F9"
        let dead: Bool          // 热键没注册上，这条绑定当前不生效
    }
    var appBindingRows: [AppBindingRow] {
        APP_BINDABLE_SLOT_ORDER.compactMap { slot in
            guard let ab = appBindings[slot] else { return nil }
            // dead 取 @Published 的 ButtonState.sentinelDead，不直接问 HotKeyCenter：
            // HotKeyCenter 不是 ObservableObject，直接读它 SwiftUI 不会因它变化而重绘。
            let s = slotState(slot)
            let title = dial.contains { $0.id == slot } ? L("旋钮 · {0}", L(s?.title ?? slot)) : L(s?.title ?? slot)
            return AppBindingRow(id: slot, title: title, appName: ab.displayName,
                                 sentinel: ab.sentinelDisplay ?? "—",
                                 dead: s?.sentinelDead ?? false)
        }
    }

    /// 注册一个哨兵热键，按下时激活对应 App。返回是否注册成功（供 SentinelPool.allocate 逐个试）。
    private func registerSentinel(slot: String, combo: SentinelCombo) -> Bool {
        HotKeyCenter.shared.register(tokens: combo.tokens, id: slot) { [weak self] in
            self?.fireAppBinding(slot: slot)
        }
    }

    /// 写哨兵组合进设备槽位。
    /// 刻意不做「回读权威回填」——applyShortcut 那套回读会把展示改回 ⌃+⌥+⌘+F9，
    /// 把「打开 App：iTerm」这行字冲掉。哨兵写的是什么我们自己最清楚，不需要问设备。
    private func writeSentinelToDevice(index: UInt8, tokens: [String]) {
        guard let d = dev else { return }
        io.async { try? d.setKeyboardShortcut(index: index, tokens: tokens) }
    }

    /// 把当前所有 App 绑定的哨兵一次性写进设备。给「不经过 applyProfile 的上线路径」补课。
    private func flushBoundSentinelsToDevice() {
        guard dev != nil else { return }
        for slot in APP_BINDABLE_SLOT_ORDER {
            guard let ab = appBindings[slot], let idx = slotIndex(slot) else { continue }
            writeSentinelToDevice(index: idx, tokens: ab.sentinelTokens)
        }
    }

    /// 哨兵热键被按下：激活绑定的 App。
    private func fireAppBinding(slot: String) {
        guard let ab = appBindings[slot] else { return }
        do {
            try AppLauncher.activate(bundleID: ab.bundleID)
            setAppMissing(slot, false)
        } catch {
            // App 被卸载了。保留绑定供用户改绑，只在行内标一下。
            setAppMissing(slot, true)
            sentinelNotice = LocalizedMessage("找不到「{0}」，它可能已被卸载。请重新选择目标 App。", ab.displayName)
        }
    }

    private func setAppMissing(_ slot: String, _ missing: Bool) {
        mutateSlotState(slot) { $0.appMissing = missing }
    }

    /// 启动时：**只把存档里的组合原样注册回来**，不换键、不写设备、不弹提示。
    ///
    /// 为什么要和 reregisterSentinels 分成两件事：换键这个动作只有连着「把新组合写进设备」
    /// 才成立，而启动这一刻 dev 还是 nil，writeSentinelToDevice 会静默什么都不做。
    /// 早先两件事合在一起，于是启动时若 F9 注册不上，程序会分配 F10、注册 F10、
    /// 把 F10 存进 appBindings、行里显示 ⌃⌥⌘F10、还弹一条「哨兵键已自动更换」——
    /// 而设备里烧的仍然是 F9。三处都在断言一次根本没发生的重写。
    ///
    /// 现在的分工：这里只还原事实——存档说是 F9 就注册 F9，注册不上就是注册不上，
    /// 那个槽在设备连上之前确实是死的，由 sentinelDead 如实标在行里。真正的换键留给
    /// applyProfile（那时 dev 在场，换完能立刻写进设备）。
    /// 顺带解决了启动时的重复劳动：init 换一次键、applyProfile 从存档改回去、再换一次。
    func registerStoredSentinels() {
        HotKeyCenter.shared.unregisterAll()
        var taken = Set<String>()
        for slot in APP_BINDABLE_SLOT_ORDER {
            guard let ab = appBindings[slot], let mk = ab.sentinelMainKey, !taken.contains(mk) else { continue }
            if registerSentinel(slot: slot, combo: SentinelCombo(mainKey: mk)) { taken.insert(mk) }
        }
        // 注册结果决定行里的 sentinelDead，逐槽刷一遍（fillState 从 HotKeyCenter 取真相）。
        // 只刷绑了 App 的槽：refreshSlotUI 传的是 from: nil，对一个配着普通快捷键的槽
        // 会把它刷成「未设置」——那不是刷新，那是抹掉。
        for slot in APP_BINDABLE_SLOT_ORDER where appBindings[slot] != nil { refreshSlotUI(slot) }
    }

    /// 按存档重注册全部哨兵热键，并在必要时换键。**只在设备可能在场时调用**（applyProfile）。
    ///
    /// 某个组合注册不上 → 自动换池中下一个 → 重写设备该槽 → 提示用户。
    ///
    /// 这条换键路径**只能兜住本进程内部的冲突**（同一个组合被两个槽位抢）。它兜不住
    /// 当初设计时想防的那种情况——用户装了新软件把这个组合占了：那种占用 register()
    /// 照样返回 true（见 HotKeyCenter.register 的注释与 2026-09-05 的实测），换键分支
    /// 根本不会进。届时两个进程都注册着同一个组合，事件归谁未测，绑定可能静默失效。
    /// 不做这件事的话，用户装个新软件就会让某个按键静默失效，而且毫无线索。
    func reregisterSentinels() {
        HotKeyCenter.shared.unregisterAll()
        var taken = Set<String>()
        var changed: [String] = []
        var changedSlots: [String] = []
        var lost: [String] = []
        // 固定顺序遍历，保证多槽冲突时的分配结果可复现（Set 的迭代顺序不稳定）
        for slot in APP_BINDABLE_SLOT_ORDER {
            guard var ab = appBindings[slot] else { continue }
            // 先试原来那个——注册得上就什么都不用改，设备侧也不用重写
            if let mk = ab.sentinelMainKey, !taken.contains(mk),
               registerSentinel(slot: slot, combo: SentinelCombo(mainKey: mk)) {
                taken.insert(mk)
                continue
            }
            guard let next = SentinelPool.allocate(taken: taken, isRegistrable: { registerSentinel(slot: slot, combo: $0) }) else {
                lost.append(ab.displayName)
                continue
            }
            taken.insert(next.mainKey)
            ab.sentinelTokens = next.tokens
            appBindings[slot] = ab
            changed.append("\(ab.displayName) → \(next.display)")
            changedSlots.append(slot)
            if let idx = slotIndex(slot) { writeSentinelToDevice(index: idx, tokens: next.tokens) }
        }
        // 注册结果决定行里的 sentinelDead——三条路径（原键留用 / 换了键 / 池耗尽）都要刷到，
        // 只刷「换了键」的那些会把上一轮遗留的 sentinelDead 挂在原键留用的槽上。
        // 同 registerStoredSentinels：只刷绑了 App 的槽，别把普通快捷键槽刷成「未设置」。
        for slot in APP_BINDABLE_SLOT_ORDER where appBindings[slot] != nil { refreshSlotUI(slot) }
        if !changed.isEmpty {
            persistAppBindings()
            saveAppBindingsToProfile(slots: changedSlots)
        }
        // changed 和 lost 可能同时非空（一批槽位里有的换成功、有的池耗尽）——合成一条消息，
        // 不能让后写的分支覆盖掉先写的，否则用户看不到「已经帮你换好了一部分」这个事实。
        switch (changed.isEmpty, lost.isEmpty) {
        case (false, true):
            sentinelNotice = LocalizedMessage("哨兵键已自动更换：{0}", changed.joined(separator: ", "))
        case (true, false):
            sentinelNotice = LocalizedMessage("哨兵键已用尽，「{0}」暂时失效。请清除部分 App 绑定后重试。", lost.joined(separator: ", "))
        case (false, false):
            sentinelNotice = LocalizedMessage("哨兵键已自动更换：{0}", changed.joined(separator: ", "))
                + LocalizedMessage("哨兵键已用尽，「{0}」暂时失效。请清除部分 App 绑定后重试。", lost.joined(separator: ", "))
        case (true, true):
            break
        }
    }
    func applyBrightness() { guard let d = dev else { return }; let v = Int(brightness); io.async { try? d.setBrightness(v) } }
    func applyMic() { guard let d = dev else { return }; let on = micOn; io.async { try? d.setMicEnable(on) }; autosave() }
    func applyLedMode() { guard let d = dev else { return }; let m = ledMode; io.async { try? d.setLedMode(m) }; autosave() }
    func applyLedBrightness() { guard let d = dev else { return }; let v = ledBrightness; io.async { try? d.setLedBrightness(v) }; autosave() }

    // MARK: 电源（待机/休眠/重启）
    // 写入后回读校验：设备没收下就把 UI 退回真实值，不给用户留「以为改了其实没改」的假象。
    func applyStandbyTime() {
        guard let d = dev else { return }
        let v = standbyTime
        io.async {
            try? d.setStandbyTime(v)
            Thread.sleep(forTimeInterval: 0.2)
            let back = retryRead(2) { d.getStandbyTime() }
            DispatchQueue.main.async { if let back, back != v { self.standbyTime = back } }
        }
        autosave()
    }
    func applySleepTime() {
        guard let d = dev else { return }
        let v = sleepTime
        io.async {
            try? d.setSleepTime(v)
            Thread.sleep(forTimeInterval: 0.2)
            let back = retryRead(2) { d.getSleepTime() }
            DispatchQueue.main.async { if let back, back != v { self.sleepTime = back } }
        }
        autosave()
    }
    /// 重启设备：会断链，心跳连续读不到→goOffline，设备回来后自动 goOnline 并重新加载。
    func rebootDevice() {
        guard let d = dev else { return }
        rebooting = true
        io.async {
            try? d.reboot()
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.rebooting = false }
        }
    }

    /// 调试面板「唤醒」按钮：发一条 deviceHeartbeat 试探能否唤醒待机后假死的厂商口链路，
    /// 隔一会儿读一次电量验证链路是否活过来，结果（成功/无响应）反馈到 UI。
    func wakeDevice() {
        guard let d = dev else { return }
        waking = true; wakeResult = nil
        io.async {
            try? d.sendHeartbeat()
            Thread.sleep(forTimeInterval: 0.3)
            let bat = retryRead(2) { d.getBatteryFull() }
            DispatchQueue.main.async {
                self.waking = false
                self.wakeResult = bat != nil ? .success : .noResponse
                self.applyBatteryReading(bat)
            }
        }
    }

    // MARK: 按键自检（接收器转发通道卡死检测）
    // dongle 里有两条互相独立的通道：按键转发（设备→2.4G→dongle→USB 键盘 report）
    // 与厂商口配置透传（主机→dongle→2.4G→设备）。前者会卡死而后者照常，于是软件层面看
    // 一切正常——USB 枚举在、配置读得到、电池读得到——唯独按键一个都出不来。只能拔插接收器冷复位。
    //
    // 判定必须由用户主动触发：「键盘口零上报」本身区分不了「转发卡死」和「用户没碰设备」，
    // 后台被动检测做不到零误报（你两小时没按，跟卡死长得一模一样）。
    enum SelfTestPhase: Equatable {
        case idle
        case waiting                          // 已取基线，等用户按键
        case done(VibeKitSelfTestVerdict)
    }
    @Published var selfTestPhase: SelfTestPhase = .idle
    @Published var selfTestRemaining = 0      // 剩余秒数，仅供 UI 显示
    private var selfTestBaseline: Int?
    private var selfTestTimer: Timer?
    static let selfTestWindow = 10            // 秒

    func startSelfTest() {
        selfTestTimer?.invalidate()
        // 探针只读 IORegistry，不打开设备、不发报文，因此不会跟自己的厂商口会话抢应答。
        guard let base = VibeKitHID.reportCounts().keyboard else {
            selfTestPhase = .done(.probeUnavailable); return
        }
        selfTestBaseline = base
        selfTestPhase = .waiting
        selfTestRemaining = Self.selfTestWindow
        var elapsed = 0.0
        selfTestTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            elapsed += 0.5
            self.selfTestRemaining = max(0, Self.selfTestWindow - Int(elapsed.rounded(.up)))
            let v = VibeKitSelfTest.verdict(baseline: self.selfTestBaseline,
                                            final: VibeKitHID.reportCounts().keyboard,
                                            online: self.connected)
            switch v {
            case .reportsSeen, .counterReset, .probeUnavailable:
                // 有上报／基线作废／探针失效都是确定结论，立刻收工，不必等满窗口。
                t.invalidate(); self.selfTestPhase = .done(v)
            case .stuckForwarding, .deviceOffline:
                // 零上报只有等满整个窗口才有意义——早判会把「还没按」当成卡死，又是一次假证据。
                if elapsed >= Double(Self.selfTestWindow) { t.invalidate(); self.selfTestPhase = .done(v) }
            }
        }
    }
    func cancelSelfTest() {
        selfTestTimer?.invalidate(); selfTestTimer = nil
        selfTestPhase = .idle; selfTestRemaining = 0
    }

    /// 是否存在"有效选中"的输入设备可供锁定——currentInput 还没刷新过("—")或系统当前没有
    /// 默认输入("（未知）"，见 VibeKitAudio.currentInputName())时不允许打开锁定。
    var canEnforce: Bool { !currentInput.isEmpty && currentInput != "—" && currentInput != "（未知）" }

    /// 锁开关此刻是否可用：已经锁着（允许解锁）或者当前有可供锁定的有效设备。
    var canToggleLock: Bool { enforceVibeMic || canEnforce }

    /// 当前默认输入设备是否正是被锁定的那个。匹配依据同 InputEnforcer：uid 优先，
    /// uid 为空（老数据、或尚未解析出 uid）时退回名字比较——不要简化成纯名字比较。
    var isLockedOnCurrent: Bool {
        guard enforceVibeMic else { return false }
        guard !enforceTargetUID.isEmpty else { return currentInput == enforceTargetName }
        return inputDevices.first { $0.name == currentInput }?.uid == enforceTargetUID
    }

    /// 某个具体输入设备（而非"当前默认输入"）是否是被锁定的目标——用于设备列表逐行判断，
    /// 跟 isLockedOnCurrent（判断当前默认输入）不是一回事，不能互相替代。
    func isLocked(_ d: AudioInput) -> Bool {
        guard enforceVibeMic else { return false }
        return enforceTargetUID.isEmpty ? d.name == enforceTargetName : d.uid == enforceTargetUID
    }

    func setEnforce(_ on: Bool) {
        if on {
            guard canEnforce else { return }   // 没有有效选中设备时不允许开锁——按钮/开关也应同步置灰
            enforceTargetName = currentInput   // 锁的是当前选中设备，不再写死 AU05
            defaults.set(currentInput, forKey: "enforceTargetName")
            // 同时解析出当前选中设备的 uid 存下——匹配依据从名字子串换成 uid 精确匹配。
            let uid = inputDevices.first { $0.name == currentInput }?.uid ?? ""
            enforceTargetUID = uid
            defaults.set(uid, forKey: "enforceTargetUID")
        }
        enforceVibeMic = on
        defaults.set(on, forKey: "enforceVibeMic")
        if on { enforcer.start(uid: enforceTargetUID, nameContains: enforceTargetName) } else { enforcer.stop() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refreshAudio() }
    }
    func startEnforceIfNeeded() {
        if enforceVibeMic { enforcer.start(uid: enforceTargetUID, nameContains: enforceTargetName) }
    }

    func setScheme(_ s: String) { scheme = s; defaults.set(s, forKey: "appearance") }
    func toggleScheme() {
        // 依当前有效外观在 亮 ↔ 暗 间切换（system 状态下按系统当前值起步）。
        let effectiveDark = scheme == "dark" || (scheme == "system" && NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        setScheme(effectiveDark ? "light" : "dark")
    }
}
