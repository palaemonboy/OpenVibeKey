// Crypto.swift — 0x55 设备通道的校验与加密。
// CRC-8/MAXIM、CRC-16/MODBUS、TEA(32 轮)。纯逻辑，无平台依赖。
import Foundation

public enum VibeKitCrypto {

    // MARK: CRC-8/MAXIM（poly 0x31 reflected = 0x8c，init 0x00）
    public static func crc8Maxim(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0x00
        for b in bytes {
            crc ^= b
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0x8c : (crc >> 1)
            }
        }
        return crc
    }

    // MARK: CRC-16/MODBUS（poly 0x8005 reflected = 0xA001，init 0xFFFF）
    public static func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xffff
        for b in bytes {
            crc ^= UInt16(b)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xa001 : (crc >> 1)
            }
        }
        return crc
    }

    // MARK: TEA（Tiny Encryption Algorithm）32 轮，delta 0x9E3779B9
    // 密钥为 16 字节，由四个小端 u32 组成。
    public static let teaKey: [UInt32] = [0xcaa5baca, 0xbc2a8a6d, 0xca5a9eba, 0x9bb88bca]
    private static let delta: UInt32 = 0x9e3779b9

    private static func encryptBlock(_ v0in: UInt32, _ v1in: UInt32, _ k: [UInt32]) -> (UInt32, UInt32) {
        var v0 = v0in, v1 = v1in, sum: UInt32 = 0
        for _ in 0..<32 {
            sum = sum &+ delta
            v0 = v0 &+ (((v1 << 4) &+ k[0]) ^ (v1 &+ sum) ^ ((v1 >> 5) &+ k[1]))
            v1 = v1 &+ (((v0 << 4) &+ k[2]) ^ (v0 &+ sum) ^ ((v0 >> 5) &+ k[3]))
        }
        return (v0, v1)
    }

    private static func decryptBlock(_ v0in: UInt32, _ v1in: UInt32, _ k: [UInt32]) -> (UInt32, UInt32) {
        var v0 = v0in, v1 = v1in, sum: UInt32 = delta &* 32
        for _ in 0..<32 {
            v1 = v1 &- (((v0 << 4) &+ k[2]) ^ (v0 &+ sum) ^ ((v0 >> 5) &+ k[3]))
            v0 = v0 &- (((v1 << 4) &+ k[0]) ^ (v1 &+ sum) ^ ((v1 >> 5) &+ k[1]))
            sum = sum &- delta
        }
        return (v0, v1)
    }

    private static func readU32LE(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o+1]) << 8) | (UInt32(b[o+2]) << 16) | (UInt32(b[o+3]) << 24)
    }
    private static func writeU32LE(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        b[o]   = UInt8(v & 0xff)
        b[o+1] = UInt8((v >> 8) & 0xff)
        b[o+2] = UInt8((v >> 16) & 0xff)
        b[o+3] = UInt8((v >> 24) & 0xff)
    }

    /// 按 8 字节 block 逐块 TEA 加密，u32 小端；不足 8 字节的尾部原样保留。
    public static func teaEncrypt(_ input: [UInt8], key: [UInt32]? = nil) -> [UInt8] {
        let k = key ?? teaKey
        var bytes = input
        var off = 0
        while off + 8 <= bytes.count {
            let (a, b) = encryptBlock(readU32LE(bytes, off), readU32LE(bytes, off + 4), k)
            writeU32LE(&bytes, off, a); writeU32LE(&bytes, off + 4, b)
            off += 8
        }
        return bytes
    }

    public static func teaDecrypt(_ input: [UInt8], key: [UInt32]? = nil) -> [UInt8] {
        let k = key ?? teaKey
        var bytes = input
        var off = 0
        while off + 8 <= bytes.count {
            let (a, b) = decryptBlock(readU32LE(bytes, off), readU32LE(bytes, off + 4), k)
            writeU32LE(&bytes, off, a); writeU32LE(&bytes, off + 4, b)
            off += 8
        }
        return bytes
    }
}
