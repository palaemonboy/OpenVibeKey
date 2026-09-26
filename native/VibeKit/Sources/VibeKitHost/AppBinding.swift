// AppBinding.swift — 槽位的主机动作绑定。保留旧类型和存储键以兼容已有配置；
// action 为 nil 时打开 App，cycleProfiles 时循环切换配置。两者共用哨兵生命周期。
//
// 放在 VibeKitHost 而非 VibeVM 旁边：它是纯 Codable 值类型，与 SentinelCombo 成对，
// 放这里 VibeKitHostProbe 才能断言它的 Codable 往返。Profile 仍在 VibeVM.swift。
import Foundation

public struct AppBinding: Codable, Equatable, Sendable {
    /// 稳定标识。不用路径——App 会被挪走、改名。
    public var bundleID: String
    /// 缓存的显示名，渲染时不必回磁盘解析。
    public var displayName: String
    /// 分配到的哨兵 token，如 ["LCtrl","LOpt","LCmd","F9"]。
    public var sentinelTokens: [String]
    /// nil preserves the meaning of bindings saved before host actions were added.
    public var action: HostAction? = nil
    public var cyclesProfiles: Bool { action == .cycleProfiles }

    public init(bundleID: String, displayName: String, sentinelTokens: [String]) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.sentinelTokens = sentinelTokens
    }

    /// 哨兵主键。tokens 结构异常（空数组）时返回 nil。
    public var sentinelMainKey: String? {
        sentinelTokens.last.flatMap { SentinelPool.modifiers.contains($0) ? nil : $0 }
    }

    /// 紧凑展示，如 "⌃⌥⌘F9"。
    public var sentinelDisplay: String? {
        sentinelMainKey.map { SentinelCombo(mainKey: $0).display }
    }
}

public enum HostAction: String, Codable, Sendable {
    case cycleProfiles
}

/// Uses the same stable name order as the profile picker. A single profile is a no-op.
public enum ProfileCycle {
    public static func next(names: [String], current: String) -> String? {
        let ordered = Array(Set(names)).sorted()
        guard ordered.count > 1 else { return nil }
        guard let index = ordered.firstIndex(of: current) else { return ordered.first }
        return ordered[(index + 1) % ordered.count]
    }
}
