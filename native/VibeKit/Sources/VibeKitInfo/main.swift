// VibeKitInfo — 里程碑 2 真机验证：IOKit 连接 VibeKey，读回设备信息并打印，对照原厂 app。
// 运行：swift run VibeKitInfo
import Foundation
import VibeKitCore
import VibeKitHID
import VibeKitAudio

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

let hid = VibeKitHID()
do {
    try hid.open()
} catch VibeKitHIDError.notFound {
    print("❌ 未找到设备。请确认 VibeKey 已插上（VID 0x\(String(VibeKitHID.vendorID, radix:16))/PID 0x\(String(VibeKitHID.productID, radix:16))）。")
    exit(1)
} catch VibeKitHIDError.openFailed(let r) {
    print("❌ 打开设备失败 IOReturn=0x\(String(UInt32(bitPattern: r), radix:16))。可能需要在『系统设置→隐私与安全性→输入监控』授权终端。")
    exit(1)
} catch {
    print("❌ \(error)"); exit(1)
}
print("✅ 已连接 VibeKey（0x55 厂商接口）\n")

func line(_ label: String, _ value: String?, _ raw: [UInt8]? = nil) {
    let v = value ?? "（无响应）"
    var s = "  \(label.padding(toLength: 12, withPad: "　", startingAt: 0))\(v)"
    if let raw { s += "   [\(hex(raw))]" }
    print(s)
}
func u32le(_ d: [UInt8]) -> Int? { d.count >= 4 ? Int(d[0]) | (Int(d[1])<<8) | (Int(d[2])<<16) | (Int(d[3])<<24) : nil }

print("== 设备信息（对照原厂 app）==")
line("型号", "AU05（VID/PID 匹配）")

if let d = hid.request(b1: 0x04, b2: 0x04) { line("固件版本", VibeKitResponses.parseVersion(d) ?? "?", d) }
else { line("固件版本", nil) }

let snChunks = hid.collect(b1: 0x01, b2: 0x0b)
let sn = VibeKitResponses.assembleChunks(snChunks)
line("序列号 SN", sn.isEmpty ? nil : sn, snChunks.first)

if let d = hid.request(b1: 0x01, b2: 0x02) {
    if let b = VibeKitResponses.parseBattery(d) { line("电量", "\(b.percent)%  ·  \(String(format: "%.2f", Double(b.voltage)/1000)) V", d) }
}
if let d = hid.request(b1: 0x06, b2: 0x20) { line("亮度", "\(d.first ?? 0)", d) }
if let d = hid.request(b1: 0x06, b2: 0x0d) { line("报告率(级)", "\(d.first ?? 0)", d) }
if let d = hid.request(b1: 0x01, b2: 0x2a) { line("麦克风", (d.first ?? 0) == 1 ? "开" : "关", d) }
if let d = hid.request(b1: 0x01, b2: 0x2c) { line("待机时长(秒)", u32le(d).map(String.init) ?? "?", d) }
if let d = hid.request(b1: 0x01, b2: 0x42) { line("睡眠时长(秒)", u32le(d).map(String.init) ?? "?", d) }
if let d = hid.request(b1: 0x01, b2: 0xfa) { line("MAC", VibeKitResponses.parseMac(d) ?? "?", d) }

print("\n== 系统麦克风 ==")
print("  当前默认输入：\(VibeKitAudio.currentInputName())")
print("  可用输入设备：")
for d in VibeKitAudio.inputDevices() { print("   - \(d.name)  [uid=\(d.uid)]") }

print("\n（把上面结果和原厂『偏好设置→设备』对照：型号 AU05 / SN C4D33I018U3670232 / 固件 4.4.0）")
hid.close()
