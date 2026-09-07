// VibeKitOracle — 用 JS 驱动生成的向量逐字节校验 VibeKitCore 移植正确性。
// 运行：swift run VibeKitOracle（CLT 无 XCTest/Testing，故以可执行 runner 承担对拍）。
// 任一不符即打印并以非零码退出。
import Foundation
import VibeKitCore

nonisolated(unsafe) var failures = 0  // 单线程 runner，安全
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok { print("  ✅ \(name)") }
    else { print("  ❌ \(name)  \(detail)"); failures += 1 }
}

func hexToBytes(_ s: String) -> [UInt8] {
    var out: [UInt8] = []; var i = s.startIndex
    while i < s.endIndex { let j = s.index(i, offsetBy: 2); out.append(UInt8(s[i..<j], radix: 16)!); i = j }
    return out
}
func bytesToHex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
func u8s(_ a: Any?) -> [UInt8] { (a as? [Any] ?? []).map { UInt8(truncatingIfNeeded: ($0 as! NSNumber).intValue) } }
func num(_ d: [String: Any], _ k: String) -> UInt8 { UInt8((d[k] as! NSNumber).intValue) }

guard let url = Bundle.module.url(forResource: "oracle-vectors", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let V = root["vectors"] as? [String: Any] else {
    print("无法加载 oracle-vectors.json"); exit(2)
}

print("== CRC-8/MAXIM ==")
for v in V["crc8"] as! [[String: Any]] {
    let got = VibeKitCrypto.crc8Maxim(hexToBytes(v["in"] as! String))
    check("crc8(\(v["in"]!))", Int(got) == (v["out"] as! NSNumber).intValue, "got \(got)")
}
print("== CRC-16/MODBUS ==")
for v in V["crc16"] as! [[String: Any]] {
    let got = VibeKitCrypto.crc16Modbus(hexToBytes(v["in"] as! String))
    check("crc16(\(v["in"]!))", Int(got) == (v["out"] as! NSNumber).intValue, "got \(got)")
}
print("== TEA ==")
do {
    let t = V["tea"] as! [String: Any]
    let plain = hexToBytes(t["plain"] as! String)
    check("tea encrypt", bytesToHex(VibeKitCrypto.teaEncrypt(plain)) == (t["cipher"] as! String))
    let cipher = hexToBytes(t["cipher"] as! String)
    check("tea decrypt==plain", bytesToHex(VibeKitCrypto.teaDecrypt(cipher)) == (t["plain"] as! String))
    let key = (t["key"] as! [Any]).map { UInt32(truncatingIfNeeded: ($0 as! NSNumber).int64Value) }
    check("tea key", VibeKitCrypto.teaKey == key)
}
print("== 明文帧 ==")
for v in V["plaintext"] as! [[String: Any]] {
    let out = VibeKitFrame.buildVendorPlaintext(b0: num(v,"b0"), b1: num(v,"b1"), b2: num(v,"b2"), b3: num(v,"b3"), payload: u8s(v["payload"]))
    check("plaintext \(v["name"]!)", bytesToHex(out) == (v["out"] as! String))
}
print("== 完整发送帧 ==")
for v in V["frames"] as! [[String: Any]] {
    let out = VibeKitFrame.sentFrame(b0: num(v,"b0"), b1: num(v,"b1"), b2: num(v,"b2"), b3: num(v,"b3"), payload: u8s(v["payload"]))
    check("frame \(v["name"]!)", bytesToHex(out) == (v["out"] as! String), "\n     got \(bytesToHex(out))\n     exp \(v["out"] as! String)")
    check("frame \(v["name"]!) len=63", out.count == VibeKitFrame.vendorReportSize)
    if let tokens = v["tokens"] as? [String] {
        let entries = (try? VibeKitKeymap.tokensToEntries(tokens)) ?? []
        var payload: [UInt8] = [0, 0x01, UInt8(entries.count)]
        for e in entries { payload += VibeKitKeymap.entryWireBytes(e) }
        check("shortcut payload \(tokens.joined(separator: "+"))", payload == u8s(v["payload"]))
        check("shortcut display \(tokens.joined(separator: "+"))", VibeKitKeymap.tokensToDisplay(tokens) == (v["display"] as! String))
    }
}
print("== 数据驱动 build（CommandMap ← protocol-commands.json）==")
check("命令表已加载", VibeKitCommands.specs.count >= 100, "count=\(VibeKitCommands.specs.count)")
for v in V["builds"] as! [[String: Any]] {
    let name = v["name"] as! String
    let args = (v["args"] as! [Any]).map { ($0 as! NSNumber).intValue }
    let out = (try? VibeKitCommands.build(name, args: args)) ?? []
    check("build \(name)", bytesToHex(out) == (v["out"] as! String), "\n     got \(bytesToHex(out))\n     exp \(v["out"] as! String)")
}

print("== 响应解析 ==")
do {
    let p = V["parse"] as! [String: Any]
    let ver = p["version"] as! [String: Any]
    check("parseVersion→4.4.0", VibeKitResponses.parseVersion(hexToBytes(ver["raw"] as! String)) == (ver["expect"] as! String))
    let chunks = (p["snChunks"] as! [String]).map { hexToBytes($0) }
    check("SN 分片拼接", VibeKitResponses.assembleChunks(chunks) == (p["snExpect"] as! String), "got \(VibeKitResponses.assembleChunks(chunks))")
    let bat = p["battery"] as! [String: Any]
    let r = VibeKitResponses.parseBattery(hexToBytes(bat["raw"] as! String))
    check("parseBattery", r?.voltage == (bat["voltage"] as! NSNumber).intValue && r?.percent == (bat["percent"] as! NSNumber).intValue, "got \(String(describing: r))")
}

print("== keymap ==")
do {
    let km = V["keymap"] as! [String: Any]
    func entries(_ a: Any) -> [KeyEntry] {
        (a as! [[String: Any]]).map { KeyEntry(page: UInt8(($0["page"] as! NSNumber).intValue), value: UInt8(($0["value"] as! NSNumber).intValue), sign: UInt8(($0["sign"] as! NSNumber).intValue)) }
    }
    check("LCmd+C entries", (try? VibeKitKeymap.tokensToEntries(["LCmd","C"])) == entries(km["LCmd+C"]!))
    check("LCtrl+LShift+A entries", (try? VibeKitKeymap.tokensToEntries(["LCtrl","LShift","A"])) == entries(km["LCtrl+LShift+A"]!))
    check("display LCmd+C", VibeKitKeymap.tokensToDisplay(["LCmd","C"]) == (km["display_LCmd+C"] as! String))
    check("display ROpt+Right", VibeKitKeymap.tokensToDisplay(["ROpt","Right"]) == (km["display_ROpt+Right"] as! String))
}
print("== 负例 ==")
do {
    var threw = false
    do { _ = try VibeKitKeymap.tokensToEntries(["Fn"]) } catch { threw = (error as? VibeKitKeymapError == .unknownKey("Fn")) }
    check("fn 被拒(unknownKey)", threw)
    threw = false
    do { _ = try VibeKitKeymap.tokensToEntries(["LCtrl","LShift","LOpt","LCmd","A"]) } catch { threw = (error as? VibeKitKeymapError == .tooManyEntries(5)) }
    check("超上限被拒(tooManyEntries)", threw)
}

print("== 电源设置（待机/休眠/重启）——真机标定 2026-09-01 ==")
do {
    // 协议表未定位这两条 SET 的 payload（payload_at "—"、args []）。真机 powerprobe 逐布局验证：
    // 命中「秒数 u32le @ payload[0]，b3=0x02」，写 600/4200 读回一致，随后原值写回复验通过。
    // 下面断言的是生产编码器本身，期望字节可手工推导。
    check("payload 600s = 58020000", bytesToHex(VibeKitCommands.powerTimePayload(seconds: 600)) == "58020000")
    check("payload 300s = 2c010000", bytesToHex(VibeKitCommands.powerTimePayload(seconds: 300)) == "2c010000")
    check("payload 3600s = 100e0000", bytesToHex(VibeKitCommands.powerTimePayload(seconds: 3600)) == "100e0000")
    check("payload 4200s = 68100000", bytesToHex(VibeKitCommands.powerTimePayload(seconds: 4200)) == "68100000")

    let zeros56 = String(repeating: "00", count: 56)
    func plaintextOf(_ b2: UInt8, _ b3: UInt8, _ payload: [UInt8]) -> String {
        bytesToHex(VibeKitFrame.buildVendorPlaintext(b0: 0x01, b1: 0x01, b2: b2, b3: b3, payload: payload))
    }
    check("待机 SET 600s 明文帧",
          plaintextOf(VibeKitCommands.standbyTimeB2, 0x02, VibeKitCommands.powerTimePayload(seconds: 600))
          == "01012c02" + "58020000" + zeros56)
    check("休眠 SET 4200s 明文帧",
          plaintextOf(VibeKitCommands.sleepTimeB2, 0x02, VibeKitCommands.powerTimePayload(seconds: 4200))
          == "01014202" + "68100000" + zeros56)
    check("重启 明文帧",
          bytesToHex(VibeKitFrame.buildVendorPlaintext(b0: 0x01, b1: 0x01, b2: 0x0c, b3: 0x00))
          == "01010c00" + String(repeating: "00", count: 60))

    // 发送帧：长度 63，且 TEA 往返能还原明文
    let sent = VibeKitCommands.buildPowerTime(b2: VibeKitCommands.standbyTimeB2, seconds: 600)
    check("待机发送帧 len=63", sent.count == VibeKitFrame.vendorReportSize)
    let round = VibeKitFrame.decodeVendorFrame(
        VibeKitFrame.encodeVendorFrame(b0: 0x01, b1: 0x01, b2: VibeKitCommands.standbyTimeB2, b3: 0x02,
                                       payload: VibeKitCommands.powerTimePayload(seconds: 600)))
    check("待机帧 TEA 往返还原明文", bytesToHex(round) == "01012c02" + "58020000" + zeros56)
    check("重启发送帧 len=63", VibeKitCommands.buildReboot().count == VibeKitFrame.vendorReportSize)

    // 边界：负数/超大值不得崩溃或回绕成危险值
    check("负秒数被夹到 0", bytesToHex(VibeKitCommands.powerTimePayload(seconds: -1)) == "00000000")
    check("超大秒数被夹到 u32 上限", bytesToHex(VibeKitCommands.powerTimePayload(seconds: Int(UInt32.max) + 99)) == "ffffffff")
}


// == 哨兵键（「打开 App」动作）==
// 哨兵机制的前提是「池里每一个组合都真能写进设备」。写不进去的组合会在真机上表现为
// 按键静默失效——所以在这里逐字节钉死，而不是等真机才发现。
// 池的定义在 VibeKitHost.SentinelPool；这里不依赖它（Oracle 只依赖 VibeKitCore），
// 故把池内容抄一份。两边不一致时以 SentinelPool 为准，并同步改这里。
print("== 哨兵键（打开 App 动作）==")
do {
    let mods = ["LCtrl", "LOpt", "LCmd"]
    let pool = ["F9", "F10", "F11", "F12", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    check("三修饰 + 主键 = 4 条目，正好压上限", mods.count + 1 == VibeKitKeymap.maxShortcutEntries)
    for mk in pool {
        let tokens = mods + [mk]
        let entries = (try? VibeKitKeymap.tokensToEntries(tokens)) ?? []
        check("哨兵 \(mk) → 4 条目（键表内且不超限）", entries.count == 4, "got \(entries.count)")
        let frame = (try? VibeKitCommands.buildShortcut(index: 0, tokens: tokens)) ?? []
        check("哨兵 \(mk) 发送帧 len=63", frame.count == VibeKitFrame.vendorReportSize)
    }
    // 逐字节钉死一条，防 payload 布局被改动而无声。
    // payload = [index=0x00, 0x01, count=0x04] + entryWireBytes×4
    //   LCtrl page3 val0x01 sign1 → 83 01
    //   LOpt  page3 val0x04 sign1 → 83 04
    //   LCmd  page3 val0x08 sign1 → 83 08
    //   F9    page2 val0x42 sign0 → 02 42
    let f9Payload: [UInt8] = [0x00, 0x01, 0x04, 0x83, 0x01, 0x83, 0x04, 0x83, 0x08, 0x02, 0x42]
    var built: [UInt8] = [0x00, 0x01, 0x04]
    for e in (try? VibeKitKeymap.tokensToEntries(mods + ["F9"])) ?? [] { built += VibeKitKeymap.entryWireBytes(e) }
    check("哨兵 F9 payload", built == f9Payload, "got \(bytesToHex(built))")
    check("哨兵 F9 明文帧",
          bytesToHex(VibeKitFrame.buildVendorPlaintext(b0: 0x01, b1: 0x06, b2: 0x50, b3: 0x04, payload: f9Payload))
          == "01065004" + "0001048301830483080242" + String(repeating: "00", count: 49))
    // TEA 往返能还原明文（与电源设置那段同款校验）
    let round = VibeKitFrame.decodeVendorFrame(
        VibeKitFrame.encodeVendorFrame(b0: 0x01, b1: 0x06, b2: 0x50, b3: 0x04, payload: f9Payload))
    check("哨兵 F9 帧 TEA 往返还原明文",
          bytesToHex(round) == "01065004" + "0001048301830483080242" + String(repeating: "00", count: 49))
}

// == 按键自检判定 ==
// 「dongle 转发通道卡死」的判定必须把三件事分开：设备发了键 / 在线但零上报 / 根本不在线。
// 混在一起就会像上次那样拿假证据下结论（离线被误判成卡死）。
print("== 按键自检判定 ==")
do {
    typealias V = VibeKitSelfTestVerdict
    func verdict(_ base: Int?, _ fin: Int?, _ online: Bool) -> V {
        VibeKitSelfTest.verdict(baseline: base, final: fin, online: online)
    }
    // 计数上涨 = 设备确实把按键发出来了，与在线标志无关（能发键本身就是最强的在线证据）
    check("上报涨了→reportsSeen(3)", verdict(2257, 2260, true) == .reportsSeen(delta: 3))
    check("上报涨了+标志离线→仍 reportsSeen", verdict(2257, 2260, false) == .reportsSeen(delta: 3))
    // 在线（电池读得到）但零上报 = 转发通道卡死，这才是提示拔插接收器的唯一条件
    check("在线+零上报→stuckForwarding", verdict(2257, 2257, true) == .stuckForwarding)
    // 不在线时零上报什么都证明不了，绝不能说卡死
    check("离线+零上报→deviceOffline", verdict(2257, 2257, false) == .deviceOffline)
    // 探针拿不到计数时，自检不可用，不假装有结论
    check("baseline 缺失→probeUnavailable", verdict(nil, 2257, true) == .probeUnavailable)
    check("final 缺失→probeUnavailable", verdict(2257, nil, true) == .probeUnavailable)
    check("两者皆缺→probeUnavailable", verdict(nil, nil, true) == .probeUnavailable)
    // 计数变小 = 设备中途重新枚举（拔插/掉线重连），基线作废。实测撞到过这个边界。
    check("计数重置但有上报→reportsSeen(4)", verdict(2257, 4, true) == .reportsSeen(delta: 4))
    check("计数重置且零上报→counterReset", verdict(2257, 0, true) == .counterReset)
    check("计数重置且零上报+离线→counterReset", verdict(2257, 0, false) == .counterReset)
    // 边界：基线为 0 的全新枚举，涨了就算通过
    check("基线0涨到1→reportsSeen(1)", verdict(0, 1, true) == .reportsSeen(delta: 1))
    check("基线0仍为0+在线→stuckForwarding", verdict(0, 0, true) == .stuckForwarding)
}

print(String(repeating: "-", count: 40))
if failures == 0 { print("全部对拍通过 ✅") ; exit(0) }
else { print("对拍失败 \(failures) 项 ❌"); exit(1) }
