// SentinelPool.swift — 哨兵键池（纯逻辑，无 IO，故可被 VibeKitHostProbe 对拍）。
//
// 为什么需要哨兵键：设备不上报按键——HooksMode(01 0b 89) 写不进去，固件未实现；
// 厂商口 0x55 除每 3 秒的电池广播外没有任何按键帧（见 docs/protocol-findings.md）。
// 所以「设备按下 → 主机收到通知」这条直路不存在，设备唯一能对外表达「按钮被按了」
// 的方式是发出真实键盘输入。于是：给槽位烧一个罕见组合键，主机注册同样组合的全局
// 热键去截获——这个罕见组合就是哨兵键。
//
// 池的取值受设备键表硬约束：
//   · 键表只到 F12（无 F13+），见 VibeKitKeymap.entryMap
//   · 单条快捷键上限 4 个条目（VibeKitKeymap.maxShortcutEntries）
// 故固定「⌃⌥⌘ 三修饰 + 1 主键」，正好压在上限上。
import Foundation
import VibeKitCore

/// 一个哨兵组合。修饰键固定为 SentinelPool.modifiers，故主键唯一标识它。
public struct SentinelCombo: Equatable, Hashable, Sendable {
    public let mainKey: String

    public init(mainKey: String) { self.mainKey = mainKey }

    /// 写设备用的完整 token 列表，如 ["LCtrl","LOpt","LCmd","F9"]。
    public var tokens: [String] { SentinelPool.modifiers + [mainKey] }

    /// 紧凑展示，如 "⌃⌥⌘F9"。
    /// 不用 VibeKitKeymap.tokensToDisplay——那个用 "+" 连接（"⌃+⌥+⌘+F9"），
    /// 放进行内小字太长。
    public var display: String {
        SentinelPool.modifiers.map(VibeKitKeymap.tokenLabel).joined() + VibeKitKeymap.tokenLabel(mainKey)
    }
}

public enum SentinelPool {
    /// 固定三修饰。顺序即写进设备的条目顺序，改动会让已有绑定的读回显示对不上。
    public static let modifiers = ["LCtrl", "LOpt", "LCmd"]

    /// 按序尝试的主键。F 键在前（更少与用户自定义冲突），数字在后。
    /// 共 14 个，远超 4 个可绑槽位。
    public static let mainKeys = ["F9", "F10", "F11", "F12", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    public static let all: [SentinelCombo] = mainKeys.map(SentinelCombo.init(mainKey:))

    /// 从池中挑第一个「没被别的槽占着，且主机侧确实注册得上」的组合。
    /// - Parameters:
    ///   - taken: 已被其它槽占用的主键集合
    ///   - isRegistrable: 试注册回调。真机上就是 HotKeyCenter.register 的返回值——
    ///     注意它有副作用：返回 true 的那个组合会**保持注册状态**，调用方直接用即可。
    ///     因为用的是 first(where:)，只有第一个成功者会被留下，不会泄漏多余注册。
    /// - Returns: 可用组合；池耗尽返回 nil。
    public static func allocate(taken: Set<String>, isRegistrable: (SentinelCombo) -> Bool) -> SentinelCombo? {
        all.first { !taken.contains($0.mainKey) && isRegistrable($0) }
    }
}
