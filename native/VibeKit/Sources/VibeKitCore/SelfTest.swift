// SelfTest.swift — 按键自检的判定逻辑（纯函数，无 IO，故可被 VibeKitOracle 对拍）。
//
// 背景：dongle 内部有两条互相独立的通道——「设备按键→2.4G→dongle→USB 键盘 report」的转发通道，
// 与「主机→dongle→2.4G→设备」的厂商口配置通道。前者的状态机会卡死而后者照常工作，
// 于是从软件层面看一切正常（USB 枚举正常、HID 接口在、配置读得到、电池读得到），
// 唯独按键一个都出不来。唯一的恢复手段是把接收器拔下再插回，给 dongle 冷复位。
//
// 判定的关键是把三件事分开——设备发了键 / 在线但零上报 / 根本不在线。
// 「键盘口零上报」本身区分不了「转发卡死」和「用户只是没碰设备」，所以自检必须由用户主动触发：
// 提示用户按键，只在这个窗口内比对计数增量。被动后台检测做不到零误报。
public enum VibeKitSelfTestVerdict: Equatable, Sendable {
    /// 设备确实发出了按键报告。窗口内新增 delta 个。
    case reportsSeen(delta: Int)
    /// 在线（厂商口读得到电池）却零上报 → 转发通道卡死，提示拔插接收器。
    case stuckForwarding
    /// 设备不在线，零上报什么都证明不了，不下卡死结论。
    case deviceOffline
    /// 窗口内计数变小且归零 → 设备中途重新枚举（拔插/掉线重连），基线作废，请重试。
    case counterReset
    /// 拿不到上报计数时，自检不可用。
    case probeUnavailable
}

public struct VibeKitSelfTest: Sendable {
    /// 由「窗口前后的键盘口累计上报数」与「设备是否在线」判定自检结论。
    /// - Parameters:
    ///   - baseline: 窗口开始时的累计上报数，nil = 探针不可用
    ///   - final: 窗口结束时的累计上报数，nil = 探针不可用
    ///   - online: 设备是否在线（App 用「厂商口读得到电池」判定）
    public static func verdict(baseline: Int?, final: Int?, online: Bool) -> VibeKitSelfTestVerdict {
        guard let baseline, let final else { return .probeUnavailable }
        if final > baseline { return .reportsSeen(delta: final - baseline) }
        // 计数变小 = IOHIDDevice 实例被重建、计数归零。此时 final 本身就是重新枚举后的增量。
        if final < baseline { return final > 0 ? .reportsSeen(delta: final) : .counterReset }
        // 零增长：能否归因于「转发卡死」完全取决于设备是否在线。
        return online ? .stuckForwarding : .deviceOffline
    }
}
