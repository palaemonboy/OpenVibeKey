// Responses.swift — 设备响应解析（data = TEA 解密后剥 4 字节头的负载）。
// 设备响应解析；字段宽度已在真实设备上验证。
import Foundation

public enum VibeKitResponses {

    /// 固件版本：b[6].b[7].b[8]。
    public static func parseVersion(_ data: [UInt8]) -> String? {
        guard data.count >= 9 else { return nil }
        return "\(data[6]).\(data[7]).\(data[8])"
    }

    /// 电量：voltage u16LE@0(mV) + percent u8@2。
    public static func parseBattery(_ data: [UInt8]) -> (percent: Int, voltage: Int)? {
        guard data.count >= 3 else { return nil }
        let voltage = Int(data[0]) | (Int(data[1]) << 8)
        let percent = max(0, min(100, Int(data[2])))
        return (percent, voltage)
    }

    /// 电量 + 充电：voltage@0(mV) / percent@2 / charging@6（真机验证 data[6] 插=01 拔=00）。
    public static func parseBatteryFull(_ data: [UInt8]) -> (percent: Int, voltage: Int, charging: Bool)? {
        guard data.count >= 3 else { return nil }
        let voltage = Int(data[0]) | (Int(data[1]) << 8)
        let percent = max(0, min(100, Int(data[2])))
        let charging = data.count > 6 && data[6] != 0
        return (percent, voltage, charging)
    }

    /// SN/UUID 分片拼接：每帧 data=[len, seg, ascii…]；按 seg 排序后拼接。
    public static func assembleChunks(_ chunks: [[UInt8]]) -> String {
        var bySeg: [Int: String] = [:]
        for d in chunks where d.count >= 2 {
            let len = Int(d[0]); let seg = Int(d[1])
            let end = min(2 + len, d.count)
            let bytes = Array(d[2..<end])
            let printable = bytes.allSatisfy { $0 >= 0x20 && $0 < 0x7f } && !bytes.isEmpty
            let str = printable ? String(bytes: bytes, encoding: .ascii) ?? "" : ""
            if bySeg[seg] == nil { bySeg[seg] = str }
        }
        return bySeg.keys.sorted().compactMap { bySeg[$0] }.joined()
    }

    /// MAC：前 6 字节。
    public static func parseMac(_ data: [UInt8]) -> String? {
        guard data.count >= 6 else { return nil }
        return data.prefix(6).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
