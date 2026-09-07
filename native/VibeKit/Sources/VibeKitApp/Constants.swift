// Constants.swift — 全局常量与自由函数：可选主键/修饰键/媒体键表、按 funcIndex 换算 token 的辅助函数、
// 麦克风名称判定、设备图标映射、Array 安全下标。均为无状态、纯搬运自 VibeKitApp.swift。
import Foundation

// 媒体键：走设备「固定功能」命令(01 06 10 04)，固件经 consumer 通道(usagePage 0x0C)发真媒体键。
// funcIndex 来自原厂 MediaKeyConverter 表。必须走这条路——键盘页的 VolumeUp/Down/Mute
// (usage 0x80/0x81/0x7F) 设备会忠实发出，但 macOS 直接无视（真机验证）。
let MEDIA_KEYS: [(token: String, label: String, funcIndex: UInt8)] = [
    ("Media:VolumeUp", "音量+", 12), ("Media:VolumeDown", "音量-", 13), ("Media:Mute", "静音/解除静音", 11),
    ("Media:PlayPause", "播放/暂停", 7), ("Media:Next", "下一曲", 8), ("Media:Prev", "上一曲", 9),
]
func mediaFuncIndex(_ token: String?) -> UInt8? { token.flatMap { t in MEDIA_KEYS.first { $0.token == t }?.funcIndex } }
/// 把设备两套存储折算成「实际生效的 tokens」。0x50 非空会压制 0x10，故 0x50 优先。
func effectiveTokens(_ slot: (shortcut: [String]?, funcIndex: UInt8)) -> [String]? {
    if let sc = slot.shortcut, !sc.isEmpty { return sc }
    if slot.funcIndex != 0, let t = mediaToken(slot.funcIndex) { return [t] }
    return slot.shortcut
}
func mediaLabel(_ funcIndex: UInt8) -> String? { MEDIA_KEYS.first { $0.funcIndex == funcIndex }?.label }
func mediaToken(_ funcIndex: UInt8) -> String? { MEDIA_KEYS.first { $0.funcIndex == funcIndex }?.token }

// 可选主键（token → 显示）。修饰键单独用开关。
// 键盘键与媒体键都能离线生效，只是走**两套不同的存储**：普通键写 0x50，媒体键写 0x10，
// 两者互斥（见 VibeKitDevice.setKeyboardShortcut / setMediaKey）。这里合成一张列表供选择，
// 具体写哪一套由 mediaFuncIndex(mainKey) 分流。
let MAIN_KEYS: [(token: String, label: String)] = {
    var a: [(String, String)] = []
    for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" { a.append((String(c), String(c))) }
    for c in "1234567890" { a.append((String(c), String(c))) }
    for i in 1...12 { a.append(("F\(i)", "F\(i)")) }
    a += [("Left","←"),("Right","→"),("Up","↑"),("Down","↓")]
    a += [("Space","空格"),("Enter","⏎"),("Esc","Esc"),("Tab","⇥"),("Delete","⌦"),("Backspace","⌫")]
    a += [("-","-"),("=","="),("[","["),("]","]"),(";",";"),("'","'"),(",",","),(".","."),("/","/"),("`","`")]
    a += MEDIA_KEYS.map { ($0.token, $0.label) }   // 媒体键走固定功能通道，见 MEDIA_KEYS
    return a
}()
let MODS: [(token: String, label: String)] = [("LCmd","⌘"),("LOpt","⌥"),("LShift","⇧"),("LCtrl","⌃")]

func isVibeMic(_ n: String) -> Bool { n.localizedCaseInsensitiveContains("vibe") || n.localizedCaseInsensitiveContains("au05") }

// 修复轮次 3：迷你面板设备行按传输类型给图标，纯展示映射，不影响 AudioInput 本身的字段语义。
func deviceTypeIcon(_ transport: String) -> String {
    switch transport {
    case "USB": return "mic.fill"
    case "内置": return "laptopcomputer"
    case "蓝牙": return "dot.radiowaves.left.and.right"
    case "虚拟": return "square.stack.3d.up"
    default: return "mic"
    }
}

// 安全下标（防灯效档位越界）。
extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - 「打开 App」动作（哨兵键机制，见 docs/superpowers/specs/2026-09-05-vibekey-open-app-action-design.md）

// 可绑定「打开 App」的槽位。旋钮左转/右转不在内——连续转动会连发哨兵键，体验极差。
//
// 顺序版是真身、Set 是派生：哨兵分配要按固定顺序遍历（Set 的迭代顺序不稳定，
// 多槽争抢同一个组合时结果会随进程变化而变），而 ShortcutEditor 只需要判断「在不在名单里」。
// 早先是「Set 常量 + 分配循环里另写一份有序字面量」，两份名单可以各改各的而不报错。
let APP_BINDABLE_SLOT_ORDER: [String] = ["btn1", "btn2", "btn3", "dialP"]
let APP_BINDABLE_SLOTS: Set<String> = Set(APP_BINDABLE_SLOT_ORDER)

// 主键下拉里代表「打开 App…」的伪 token。不是设备键表里的键，永远不会被写进设备；
// 双下划线前缀保证不会和 MAIN_KEYS 里任何真 token 撞名。
let OPEN_APP_TOKEN = "__openApp__"

// 已绑 App 时，下拉里「换一个 App」用的伪 token。
// 为什么要单独一个：已绑时打勾的是 OPEN_APP_TOKEN（标签为当前 App 名），而 SwiftUI
// 对「选中已经选中的那项」不会回调 set —— 只有一项的话它就是个死项，用户点了没反应，
// 得先切成别的键再切回来才能换绑。
let OPEN_APP_PICK_TOKEN = "__openAppPick__"
