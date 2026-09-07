// Frame.swift — 0x55 设备帧的组装。
// 明文 [b0 b1 b2 b3][payload…] 补 0 到 64 → 整帧 TEA → 取前 63 字节发送（reportId 0x55 由 HID 层单独传）。
import Foundation

public enum VibeKitFrame {
    /// in/out report 负载长度（HID 描述符：63 字节）。
    public static let vendorReportSize = 63

    /// 构造 64 字节明文缓冲：前 4 字节 header，其后 payload，右侧补 0。
    public static func buildVendorPlaintext(
        b0: UInt8 = 0x01, b1: UInt8, b2: UInt8, b3: UInt8,
        payload: [UInt8] = [], size: Int = 64
    ) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: size)
        buf[0] = b0; buf[1] = b1; buf[2] = b2; buf[3] = b3
        for (i, p) in payload.prefix(size - 4).enumerated() { buf[4 + i] = p }
        return buf
    }

    /// 明文 → 整块 TEA 加密（64 字节密文）。
    public static func encodeVendorFrame(
        b0: UInt8 = 0x01, b1: UInt8, b2: UInt8, b3: UInt8,
        payload: [UInt8] = [], size: Int = 64
    ) -> [UInt8] {
        VibeKitCrypto.teaEncrypt(buildVendorPlaintext(b0: b0, b1: b1, b2: b2, b3: b3, payload: payload, size: size))
    }

    /// 实际发送帧：TEA 密文取前 63 字节（等价于丢掉第 8 个 TEA block 的最后 1 字节）。
    public static func sentFrame(
        b0: UInt8 = 0x01, b1: UInt8, b2: UInt8, b3: UInt8, payload: [UInt8] = []
    ) -> [UInt8] {
        Array(encodeVendorFrame(b0: b0, b1: b1, b2: b2, b3: b3, payload: payload).prefix(vendorReportSize))
    }

    /// 设备返回帧解密：TEA 解密 → 明文（前 4 字节 header，其后数据）。
    public static func decodeVendorFrame(_ cipher: [UInt8]) -> [UInt8] {
        VibeKitCrypto.teaDecrypt(cipher)
    }
}
