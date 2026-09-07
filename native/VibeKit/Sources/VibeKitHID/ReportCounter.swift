// ReportCounter.swift — 只读 IORegistry 取 dongle 各 HID 接口的累计输入报告数。
//
// 用途：按键自检要回答「设备到底有没有把按键发出来」。这个问题不能靠打开设备去听——
// 厂商口是「发请求→等配对应答」的模式，多个客户端同时开着会把对方的应答吃掉
// （实测过：CLI 和 App 同时读电池，双方都读不到，App 于是误判设备离线）。
// 读 IORegistry 属性不打开设备、不发任何报文，因此与 App 自己的厂商口会话零冲突。
//
// 系统更新后此计数器可能不可用。拿不到就返回 nil，
// 由上层把自检标为不可用——不猜、不假装有结论。
import Foundation
import IOKit
import IOKit.hid

extension VibeKitHID {
    /// dongle 键盘/消费/鼠标接口的累计输入报告数（设备发出的按键、媒体键都计入这里）。
    /// nil = 探针不可用（设备不在，或 DebugState / InputReportCount 拿不到）。
    public static func keyboardInputReportCount() -> Int? {
        reportCounts().keyboard
    }

    /// 同时取键盘口与厂商口计数，供诊断展示。任一项拿不到即为 nil。
    /// 厂商口计数会随设备每 2~3 秒一次的电池广播稳定上涨，可用来佐证链路是活的。
    public static func reportCounts() -> (keyboard: Int?, vendor: Int?) {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOHIDDevice"), &iter) == KERN_SUCCESS,
              iter != 0 else { return (nil, nil) }
        defer { IOObjectRelease(iter) }

        var keyboard: Int?
        var vendor: Int?
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            defer { IOObjectRelease(svc); svc = IOIteratorNext(iter) }
            guard (property(svc, "VendorID") as? NSNumber)?.intValue == vendorID else { continue }
            guard let count = (property(svc, "DebugState") as? [String: Any])?["InputReportCount"],
                  let c = (count as? NSNumber)?.intValue else { continue }
            // 靠报告描述符区分接口，**不能用 PrimaryUsagePage**——那个字段只反映第一个
            // top-level collection，而这台设备的键盘 collection 恰恰藏在
            // PrimaryUsagePage=12(consumer) 的接口里第三个位置。据此判断会把能发键的接口判成不能。
            let isVendorPort = (property(svc, "ReportDescriptor") as? Data).map {
                $0.count >= 3 && $0[0] == 0x06 && $0[1] == 0xfc && $0[2] == 0xff
            } ?? false
            // 取最大值而非累加：同一物理接口若被枚举出多个条目，累加会翻倍；
            // 自检只关心「有没有增长」，单调递增的最大值足够且不会虚高。
            if isVendorPort { vendor = max(vendor ?? c, c) } else { keyboard = max(keyboard ?? c, c) }
        }
        return (keyboard, vendor)
    }

    private static func property(_ svc: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
