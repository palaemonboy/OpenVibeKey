// SentinelBookkeeping.swift — 「设备上还欠着一次哨兵清除」这本账的纯逻辑部分。
//
// 为什么需要这本账：哨兵组合键是**程序自己**烧进设备槽位的，不是用户配的快捷键。
// 一旦主机侧不再监听某个槽（切到没配过这个槽的配置、离线解绑、绑定被丢弃），
// 设备里那串 ⌃⌥⌘F9 还在——按下去会原样打给前台 App，而界面显示「未设置」。
// 已知的「退出 App 后哨兵泄漏」在 App 还活着的时候就发生了，且界面还在否认它。
//
// 所以：丢绑定时若设备不在场（写不进去），把槽位记进这本账；设备回来时补清。
// 账要持久化——用户很可能在设备回来之前就退出了 App。
//
// 这里只放**判定**，不碰 IO 与 UserDefaults：谁该记账、记下的哪些还真该清，
// 都是能脱机对拍的纯函数（VibeKitHostProbe 覆盖）。真正的写设备与落盘在 VibeVM。
import Foundation

public enum SentinelBookkeeping {
    /// 一次配置切换里，哪些槽「刚刚丢掉了 App 绑定」。
    ///
    /// 只看绑定的有无，不看新配置往这个槽写了什么——那要等到真要清的时候再复核
    /// （见 drainPlan）。因为记账与补清之间可能隔着一次退出重启，中途什么都可能变。
    ///
    /// - Parameters:
    ///   - previous: 切换前的槽位 → 绑定
    ///   - next: 切换后的槽位 → 绑定
    ///   - order: 可绑槽位的固定顺序（结果按它排，保证可复现）
    public static func slotsLosingBinding(previous: [String: AppBinding],
                                          next: [String: AppBinding],
                                          order: [String]) -> [String] {
        order.filter { previous[$0] != nil && next[$0] == nil }
    }

    /// 补清计划：账上这些槽，哪些真要往设备写空、哪些只销账不写。
    ///
    /// 复核是必须的：记账之后这个槽可能已经被别的东西占住了——用户重新绑了 App、
    /// 配了媒体键、或者新配置给它写了一条普通快捷键。此时再写空就是把刚落地的配置抹掉。
    ///
    /// - Parameters:
    ///   - pending: 账上的槽位集合
    ///   - order: 可绑槽位的固定顺序（clear 按它排，保证写设备的顺序可复现）
    ///   - isVacant: 该槽此刻是否确实空着（没绑 App、没媒体键、没普通快捷键）
    /// - Returns: clear = 要往设备写空的槽（有序）；settled = 本次处理完可以从账上划掉的全部槽。
    ///   settled 总是包含 clear——一次 drain 之后整本账都结清，不留半笔。
    public static func drainPlan(pending: Set<String>,
                                 order: [String],
                                 isVacant: (String) -> Bool) -> (clear: [String], settled: Set<String>) {
        let clear = order.filter { pending.contains($0) && isVacant($0) }
        return (clear, pending)
    }
}
