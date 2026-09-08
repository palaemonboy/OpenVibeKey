// CommandMap.swift — 数据驱动命令表：加载 protocol-commands.json，
// 按每条命令的 header + 参数落位(arg→wire→width,LE) 生成发送帧。
// 变长命令(SN/UUID/快捷键/上传)不走通用 build，另有专用构造。
import Foundation

public struct CommandArg: Codable, Sendable {
    public let arg: Int?     // ObjC 参数序号(1 起)；null 表示未识别
    public let wire: Int     // 帧内字节偏移
    public let width: Int    // 字节数(1/2/4，LE)
}

public struct CommandSpec: Codable, Sendable {
    public let name: String
    public let header: [Int]         // [b0,b1,b2,b3]
    public let direction: String     // get/set
    public let args: [CommandArg]?
    public let variable: Bool?
}

public enum VibeKitCommandError: Error, Equatable {
    case unknownCommand(String)
    case variableCommand(String)     // 需专用构造(如快捷键)
    case missingArg(String, Int)
}

public enum VibeKitCommands {
    private struct Table: Codable { let commands: [CommandSpec] }

    /// SwiftPM's generated `Bundle.module` looks for a target bundle beside the
    /// `.app` itself. A normal signed macOS app must keep it in
    /// `Contents/Resources`, so search both standard packaged and SwiftPM-run
    /// layouts without ever initializing that generated accessor.
    private static func resourceURL(named name: String, extension ext: String) -> URL? {
        let bundleName = "VibeKit_VibeKitCore.bundle"
        let roots = [Bundle.main.resourceURL, Bundle.main.bundleURL]
        for root in roots.compactMap({ $0 }) {
            if let bundle = Bundle(path: root.appendingPathComponent(bundleName).path),
               let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    public static let specs: [String: CommandSpec] = {
        guard let url = resourceURL(named: "protocol-commands", extension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(Table.self, from: data) else {
            return [:]
        }
        var m: [String: CommandSpec] = [:]
        for c in table.commands { m[c.name] = c }
        return m
    }()

    public static func spec(_ name: String) -> CommandSpec? { specs[name] }

    /// 通用 build：按命令表把有序参数放入 payload（LE），生成 63 字节发送帧。
    /// args 顺序对应 ObjC 参数序（args[0]=arg1）。变长命令请用专用构造。
    public static func build(_ name: String, args: [Int] = []) throws -> [UInt8] {
        guard let s = specs[name] else { throw VibeKitCommandError.unknownCommand(name) }
        if s.variable == true { throw VibeKitCommandError.variableCommand(name) }
        let argSpecs = s.args ?? []
        // wire 是帧内偏移(含 4 字节头)；payload 从帧偏移 4 放起，故 payload 下标 = wire-4。
        var payloadLen = 0
        for a in argSpecs where a.wire >= 4 { payloadLen = max(payloadLen, a.wire - 4 + a.width) }
        var payload = [UInt8](repeating: 0, count: payloadLen)
        for a in argSpecs {
            guard let idx = a.arg, idx >= 1, a.wire >= 4 else { continue }
            guard idx - 1 < args.count else { throw VibeKitCommandError.missingArg(name, idx) }
            var v = args[idx - 1]
            let off = a.wire - 4
            for k in 0..<a.width { payload[off + k] = UInt8(truncatingIfNeeded: v); v >>= 8 } // LE
        }
        let h = s.header
        return VibeKitFrame.sentFrame(b0: UInt8(h[0]), b1: UInt8(h[1]), b2: UInt8(h[2]), b3: UInt8(h[3]), payload: payload)
    }

    // MARK: 电源设置（待机/休眠/重启）
    // 协议表里 setDeviceStandbyTimeMessage:/setDeviceSleepTimeMessage: 的 payload 未定位
    // （payload_at "—"、args []），故不能走通用 build。真机 powerprobe 逐候选布局验证
    // （2026-09-01，AU05 固件 4.4.0）：命中「秒数 u32 小端 @ payload[0]，b3=0x02」——
    // 写 600/4200 读回一致，原值写回复验通过。GET 侧 (b3=0x01) 早已确认同为 u32le。
    public static let standbyTimeB2: UInt8 = 0x2c   // 待机 01 01 2c
    public static let sleepTimeB2: UInt8 = 0x42     // 休眠 01 01 42

    /// 待机/休眠时长 payload：秒数 u32 小端。越界值夹紧，不回绕（回绕可能得到极小值把设备设成秒睡）。
    public static func powerTimePayload(seconds: Int) -> [UInt8] {
        let v = UInt32(clamping: seconds)
        return (0..<4).map { UInt8(truncatingIfNeeded: v >> (8 * UInt32($0))) }
    }

    /// 待机/休眠时长写入帧。b2 取 standbyTimeB2 或 sleepTimeB2。
    public static func buildPowerTime(b2: UInt8, seconds: Int) -> [UInt8] {
        VibeKitFrame.sentFrame(b0: 0x01, b1: 0x01, b2: b2, b3: 0x02,
                               payload: powerTimePayload(seconds: seconds))
    }

    /// 设备重启帧：01 01 0c 00，无 payload。
    public static func buildReboot() -> [UInt8] {
        VibeKitFrame.sentFrame(b0: 0x01, b1: 0x01, b2: 0x0c, b3: 0x00)
    }

    /// 快捷键专用构造：tokens → [index,0x01,num,(pageSign,value)×num] → 发送帧。
    public static func buildShortcut(index: UInt8, tokens: [String]) throws -> [UInt8] {
        let entries = try VibeKitKeymap.tokensToEntries(tokens)
        var payload: [UInt8] = [index, 0x01, UInt8(entries.count)]
        for e in entries { payload += VibeKitKeymap.entryWireBytes(e) }
        return VibeKitFrame.sentFrame(b0: 0x01, b1: 0x06, b2: 0x50, b3: 0x04, payload: payload)
    }
}
