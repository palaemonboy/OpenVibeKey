// VibeKitDevice.swift — 高层设备 API（读/写），基于 VibeKitHID + VibeKitCore CommandMap。
// 对应网页驱动的 VibeKey 类。写命令为 SET（发送即可）；读回用对应 GET。
import Foundation
import VibeKitCore

public final class VibeKitDevice: @unchecked Sendable {
    public let hid: VibeKitHID
    public init(_ hid: VibeKitHID) { self.hid = hid }

    // 3 个圆键下标：btn1=0 / btn2=1 / btn3=2。
    public static func keyIndex(_ id: String) -> UInt8? {
        ["btn1": 0, "btn2": 1, "btn3": 2][id]
    }

    // MARK: 离线快捷键
    /// 写一个按键的快捷键（tokens 空则清除）。设备每键单槽。
    public func setShortcut(index: UInt8, tokens: [String]) throws {
        if tokens.isEmpty {
            let frame = VibeKitFrame.sentFrame(b0: 0x01, b1: 0x06, b2: 0x50, b3: 0x04, payload: [index, 0x01, 0x00])
            try hid.send(frame)
        } else {
            try hid.send(try VibeKitCommands.buildShortcut(index: index, tokens: tokens))
        }
    }

    /// 给某 index 指派「固定功能」(原厂 MediaKeyConverter 表)：11=静音 12=音量+ 13=音量-，
    /// 7=播放/暂停 8=下一曲 9=上一曲。帧 01 06 10 04 | 00 buttonId funcIndex（byte4 固定 0）。
    /// 设备据此经 consumer 通道(usagePage 0x0C)发真媒体键，macOS 原生响应（键盘页音量键 macOS 不认）。
    /// 与 0x50 快捷键共用 index 空间，但是**两套独立存储**：0x50 非空时会压制 0x10，
    /// 写固定功能并不会清掉 0x50。要让媒体键生效必须先清 0x50 —— 用 setMediaKey 而非直接调本方法。
    public func setButtonFixedFunction(index: UInt8, funcIndex: UInt8) throws {
        try hid.send(VibeKitFrame.sentFrame(b0: 0x01, b1: 0x06, b2: 0x10, b3: 0x04, payload: [0x00, index, funcIndex]))
    }

    /// 读某 index 的「固定功能」funcIndex（0 = 无）。0x50 读不到固定功能，两者是独立的两套存储，需分开读。
    /// 帧 01 06 10 01 | 00 index，响应 data = [00, index, funcIndex]（真机实测 2026-08-31，
    /// 与请求同布局；docs 里那条 off=0 是 inferred 推断值，实测为 off=2）。
    public func getButtonFixedFunction(index: UInt8) -> UInt8? {
        guard let d = hid.request(b1: 0x06, b2: 0x10, dir: 0x01, payload: [0x00, index]), d.count >= 3 else { return nil }
        return d[2]
    }

    /// 设媒体键（推荐入口）：写 0x10 固定功能**前先清空该 index 的 0x50**。
    /// 必须清 —— 0x50 非空会压制 0x10，不清则媒体键不生效（真机实测 2026-08-31：
    /// btn1 清空 0x50 后 0x10=12 才发出音量+）。两条命令间留间隔，避免固件丢帧。
    public func setMediaKey(index: UInt8, funcIndex: UInt8) throws {
        try setShortcut(index: index, tokens: [])
        Thread.sleep(forTimeInterval: 0.12)
        try setButtonFixedFunction(index: index, funcIndex: funcIndex)
    }

    /// 设普通键盘快捷键（推荐入口）：写 0x50 前先把 0x10 固定功能清 0，避免两套存储同时有值。
    /// 设备经键盘 collection 直接发出，离线生效、不需要上位机。
    /// 两个例外不能走这里：**音量/静音**（macOS 无视键盘页的这三个 usage，必须用 setMediaKey 走 0x10）、
    /// **fn/🌐**（原厂 app 是在主机侧注入的，设备发不出来）。
    public func setKeyboardShortcut(index: UInt8, tokens: [String]) throws {
        try setButtonFixedFunction(index: index, funcIndex: 0)
        Thread.sleep(forTimeInterval: 0.12)
        try setShortcut(index: index, tokens: tokens)
    }

    /// 读回某键的快捷键 tokens（读不到返回 nil）。
    public func getShortcut(index: UInt8) -> [String]? {
        guard let d = hid.request(b1: 0x06, b2: 0x50, dir: 0x01, payload: [index]), d.count >= 3 else { return nil }
        let num = Int(d[2])
        guard num > 0 else { return [] }
        var tokens: [String] = []
        for i in 0..<num {
            let o = 3 + 2 * i
            guard o + 1 < d.count else { break }
            let e = VibeKitKeymap.entryFromWire(d[o], d[o + 1])
            guard let t = VibeKitKeymap.entryToToken(e) else { return nil } // 含未知条目视为读取失败
            tokens.append(t)
        }
        return tokens
    }

    /// 一次读出某 index 的两套存储。判断谁实际生效的规则：
    /// **0x50 非空 → 0x50 生效并压制 0x10**；0x50 为空且 funcIndex != 0 → 那个固定功能（媒体键）生效。
    /// 调用方据此还原「设备当前实际行为」，不要只读 0x50（那样会把被压制的媒体键漏掉，反之亦然）。
    public func getSlot(index: UInt8) -> (shortcut: [String]?, funcIndex: UInt8) {
        let sc = getShortcut(index: index)
        let ff = getButtonFixedFunction(index: index) ?? 0
        return (sc, ff)
    }

    // MARK: 全局设置（数据驱动 build）
    public func setBrightness(_ v: Int) throws { try hid.send(try VibeKitCommands.build("setDeviceBrightnessMessage:", args: [v])) }
    public func setReportRate(_ level: Int) throws { try hid.send(try VibeKitCommands.build("setDeviceReportRateMessage:", args: [level])) }
    public func setMicEnable(_ on: Bool) throws { try hid.send(try VibeKitCommands.build("setDeviceMicrophoneEnableMessage:", args: [on ? 1 : 0])) }

    // MARK: 指示灯（灯效）——设置当前模式与全亮模式亮度
    // 共用 header 01 0b 88 04；wire4 为子命令：0x01=设模式(mode@wire6) / 0x02=设全亮亮度(level@wire7)。
    /// 灯效模式（0/1/2 = 全灭/全亮/工作，具体对应以真机为准）。
    public func setLedMode(_ mode: Int) throws {
        try hid.send(VibeKitFrame.sentFrame(b0: 0x01, b1: 0x0b, b2: 0x88, b3: 0x04, payload: [0x01, 0x00, UInt8(mode & 0xff)]))
    }
    /// 全亮模式亮度（0…100）。
    public func setLedBrightness(_ level: Int) throws {
        try hid.send(VibeKitFrame.sentFrame(b0: 0x01, b1: 0x0b, b2: 0x88, b3: 0x04, payload: [0x02, 0x00, 0x00, UInt8(max(0, min(100, level)))]))
    }
    /// 读指示灯全部参数（原始字节，供标定 mode/亮度布局）。
    public func getIndicatorRaw() -> [UInt8]? { hid.request(b1: 0x0b, b2: 0x88) }
    // 工作模式各灯 type：0=灭 / 1=常亮 / 2=呼吸。灯序 [btn1,btn2,btn3,dial]=index 0..3。
    // 帧：01 0b 88 04 | 04(fieldMask=type) focusIndex 00 00 | 各灯 value@payload[4+5*i]。
    // 必须一次带上全部 4 灯当前 type，否则未填的槽会被写 0、把其它灯清掉（联动冲突 bug）。
    public func setLedTypes(_ types: [Int], focus ledIndex: Int) throws {
        // 写全字段块（fieldMask=0x7c=type|workTime|breatheLevel|breatheBright|alwaysOn）。
        // 每灯用 btn1 实测可持续呼吸的参数 [type, 0x0a, 0x02, 0x02, 0x02]，避免只写 type 时呼吸没参数几秒即灭。
        var payload = [UInt8](repeating: 0, count: 24)
        payload[0] = 0x7c
        payload[1] = UInt8(ledIndex)
        for i in 0..<min(4, types.count) {
            let base = 4 + 5 * i
            payload[base] = UInt8(types[i] & 0xff)  // type
            payload[base + 1] = 0x0a                // workTime
            payload[base + 2] = 0x02                // breatheLevel
            payload[base + 3] = 0x02                // breatheBright
            payload[base + 4] = 0x02                // alwaysOnBright
        }
        try hid.send(VibeKitFrame.sentFrame(b0: 0x01, b1: 0x0b, b2: 0x88, b3: 0x04, payload: payload))
    }
    /// 读回 4 灯 type（[btn1,btn2,btn3,dial]），来自 getIndicatorRaw 的 data[4+5i]。
    public func getLedTypes() -> [Int]? {
        guard let d = getIndicatorRaw(), d.count >= 24 else { return nil }
        return (0..<4).map { Int(d[4 + 5 * $0]) }
    }
    /// 指示灯呼吸开关（DialNeoIndicatorLightBreatheEnable）01 01 43 04|en。
    public func getIndicatorBreathe() -> Bool? { hid.request(b1: 0x01, b2: 0x43)?.first.map { $0 != 0 } }
    public func setIndicatorBreathe(_ on: Bool) throws {
        try hid.send(VibeKitFrame.sentFrame(b0: 0x01, b1: 0x01, b2: 0x43, b3: 0x04, payload: [on ? 1 : 0]))
    }

    // MARK: 电源（待机 / 休眠 / 重启）
    // 待机=息屏进低功耗但仍可被按键唤醒；休眠=更深一级。两者单位都是秒，u32le。
    // 注意：待机默认 300 秒——闲置超时后厂商口会不响应（见 docs「待机污染诊断」），
    // 调长可显著减少真机调试时反复物理唤醒设备的麻烦。
    public func getStandbyTime() -> Int? { Self.parseU32(hid.request(b1: 0x01, b2: VibeKitCommands.standbyTimeB2)) }
    public func getSleepTime() -> Int? { Self.parseU32(hid.request(b1: 0x01, b2: VibeKitCommands.sleepTimeB2)) }

    public func setStandbyTime(_ seconds: Int) throws {
        try hid.send(VibeKitCommands.buildPowerTime(b2: VibeKitCommands.standbyTimeB2, seconds: seconds))
    }
    public func setSleepTime(_ seconds: Int) throws {
        try hid.send(VibeKitCommands.buildPowerTime(b2: VibeKitCommands.sleepTimeB2, seconds: seconds))
    }

    /// 重启设备。会断开连接，上层需重连（心跳会自动恢复）。
    public func reboot() throws { try hid.send(VibeKitCommands.buildReboot()) }

    /// 发一条 deviceHeartbeat（帧 06 01 23 00，无 payload）。
    /// 用于试探能否唤醒待机超时后假死的厂商口链路（见 docs「待机会污染真机诊断」：
    /// 闲置后厂商口对所有 GET 无响应，USB 层面仍正常）。发完后应隔一会儿再读一次命令验证链路是否恢复。
    public func sendHeartbeat() throws {
        try hid.send(VibeKitFrame.sentFrame(b0: 0x06, b1: 0x01, b2: 0x23, b3: 0x00))
    }

    private static func parseU32(_ d: [UInt8]?) -> Int? {
        guard let d, d.count >= 4 else { return nil }
        return Int(UInt32(d[0]) | (UInt32(d[1]) << 8) | (UInt32(d[2]) << 16) | (UInt32(d[3]) << 24))
    }

    // MARK: 读回（供设置窗回填）
    public func getBrightness() -> Int? { hid.request(b1: 0x06, b2: 0x20)?.first.map(Int.init) }
    public func getReportRate() -> Int? { hid.request(b1: 0x06, b2: 0x0d)?.first.map(Int.init) }
    public func getMicEnable() -> Bool? { hid.request(b1: 0x01, b2: 0x2a)?.first.map { $0 == 1 } }
    // 麦克风降噪级别（GET 01 01 90 响应 [level,u16 low,u16 high]，真机验证；SET 01 01 90 04|level）。
    public func getMicNRLevel() -> Int? { hid.request(b1: 0x01, b2: 0x90)?.first.map(Int.init) }
    public func setMicNRLevel(_ level: Int) throws {
        try hid.send(try VibeKitCommands.build("setDeviceMicNRLevel:lowParam:highParam:", args: [max(0, min(255, level))]))
    }
    // 麦克风 UI 闪烁提示（把 btn1 的 LED 当麦克风指示灯周期闪烁）。SET 01 06 24 02|mode，mode=0 关闭。
    public func getMicUiFlick() -> Bool? { hid.request(b1: 0x06, b2: 0x24)?.first.map { $0 != 0 } }
    public func setMicUiFlick(_ on: Bool) throws {
        try hid.send(VibeKitFrame.sentFrame(b0: 0x01, b1: 0x06, b2: 0x24, b3: 0x02, payload: [on ? 1 : 0]))
    }
    public func getVersion() -> String? { hid.request(b1: 0x04, b2: 0x04).flatMap(VibeKitResponses.parseVersion) }
    public func getSN() -> String? { let s = VibeKitResponses.assembleChunks(hid.collect(b1: 0x01, b2: 0x0b)); return s.isEmpty ? nil : s }
    // RX（接收端 dongle）：SN 06 02 81（单帧 ASCII，非分片）、固件 06 02 03（同 TX 15字节 b6.b7.b8）。
    // 有线直连（无 2.4G 接收端）时无人应答 → 返回 nil（属正常 N/A）。
    public func getDongleSN() -> String? {
        guard let d = hid.request(b0: 0x06, b1: 0x02, b2: 0x81) else { return nil }
        let printable = d.filter { $0 >= 0x20 && $0 < 0x7f }
        let s = (String(bytes: printable, encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }
    public func getDongleVersion() -> String? { hid.request(b0: 0x06, b1: 0x02, b2: 0x03).flatMap(VibeKitResponses.parseVersion) }
    public func getBattery() -> (percent: Int, voltage: Int)? { hid.request(b1: 0x01, b2: 0x02).flatMap(VibeKitResponses.parseBattery) }
    // 一次读电池命令(01 01 02)，同帧解出 电量/电压/充电，避免多次请求抢响应。
    public func getBatteryFull() -> (percent: Int, voltage: Int, charging: Bool)? {
        hid.request(b1: 0x01, b2: 0x02).flatMap(VibeKitResponses.parseBatteryFull)
    }
}
