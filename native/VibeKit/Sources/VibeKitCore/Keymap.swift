// Keymap.swift — 快捷键 token ↔ 设备条目 {page,value,sign}。
// 普通键 page=2；修饰键 page=3、左 sign=1/右 sign=0。
// fn/🌐 不收录（真机确认设备无法经 HID 发出，见 docs/protocol-findings.md）。
import Foundation

public struct KeyEntry: Equatable, Sendable {
    public let page: UInt8
    public let value: UInt8
    public let sign: UInt8
    public init(page: UInt8, value: UInt8, sign: UInt8) {
        self.page = page; self.value = value; self.sign = sign
    }
}

public enum VibeKitKeymapError: Error, Equatable {
    case unknownKey(String)      // 设备键表无对应条目
    case tooManyEntries(Int)     // 超过单条快捷键上限
}

public enum VibeKitKeymap {
    /// 单条快捷键最多 4 个条目（官方 app 同款约束：至多 3 修饰 + 1 主键）。
    public static let maxShortcutEntries = 4

    private static func mod(_ v: UInt8, _ s: UInt8) -> KeyEntry { KeyEntry(page: 3, value: v, sign: s) }
    private static func key(_ v: UInt8) -> KeyEntry { KeyEntry(page: 2, value: v, sign: 0) }

    public static let entryMap: [String: KeyEntry] = [
        // 修饰键（page=3；左 sign=1 / 右 sign=0）
        "LCtrl": mod(0x01, 1), "LShift": mod(0x02, 1), "LOpt": mod(0x04, 1), "LCmd": mod(0x08, 1),
        "RCtrl": mod(0x10, 0), "RShift": mod(0x20, 0), "ROpt": mod(0x40, 0), "RCmd": mod(0x80, 0),
        // 字母
        "A": key(0x04), "B": key(0x05), "C": key(0x06), "D": key(0x07), "E": key(0x08), "F": key(0x09),
        "G": key(0x0a), "H": key(0x0b), "I": key(0x0c), "J": key(0x0d), "K": key(0x0e), "L": key(0x0f),
        "M": key(0x10), "N": key(0x11), "O": key(0x12), "P": key(0x13), "Q": key(0x14), "R": key(0x15),
        "S": key(0x16), "T": key(0x17), "U": key(0x18), "V": key(0x19), "W": key(0x1a), "X": key(0x1b),
        "Y": key(0x1c), "Z": key(0x1d),
        // 数字（主键盘）
        "1": key(0x1e), "2": key(0x1f), "3": key(0x20), "4": key(0x21), "5": key(0x22),
        "6": key(0x23), "7": key(0x24), "8": key(0x25), "9": key(0x26), "0": key(0x27),
        // 控制键
        "Enter": key(0x28), "Esc": key(0x29), "Backspace": key(0x2a), "Tab": key(0x2b), "Space": key(0x2c),
        "CapsLock": key(0x39), "Delete": key(0x4c),
        // 符号
        "-": key(0x2d), "=": key(0x2e), "[": key(0x2f), "]": key(0x30), "\\": key(0x31),
        ";": key(0x33), "'": key(0x34), "`": key(0x35), ",": key(0x36), ".": key(0x37), "/": key(0x38),
        // 功能键
        "F1": key(0x3a), "F2": key(0x3b), "F3": key(0x3c), "F4": key(0x3d), "F5": key(0x3e), "F6": key(0x3f),
        "F7": key(0x40), "F8": key(0x41), "F9": key(0x42), "F10": key(0x43), "F11": key(0x44), "F12": key(0x45),
        // 导航
        "Up": key(0x52), "Down": key(0x51), "Left": key(0x50), "Right": key(0x4f),
        "Home": key(0x4a), "End": key(0x4d), "PageUp": key(0x4b), "PageDown": key(0x4e),
        // 媒体
        "VolumeUp": key(0x80), "VolumeDown": key(0x81), "Mute": key(0x7f),
    ]

    public static func isModifierToken(_ token: String) -> Bool {
        entryMap[token]?.page == 3
    }

    /// token 列表 → 设备条目列表。未知 token 抛 unknownKey；超上限抛 tooManyEntries。
    public static func tokensToEntries(_ tokens: [String]) throws -> [KeyEntry] {
        var out: [KeyEntry] = []
        for t in tokens {
            guard let e = entryMap[t] else { throw VibeKitKeymapError.unknownKey(t) }
            out.append(e)
        }
        if out.count > maxShortcutEntries { throw VibeKitKeymapError.tooManyEntries(out.count) }
        return out
    }

    /// 条目 → 帧内 2 字节 [(page&0x7f)|(sign<<7), value]。
    public static func entryWireBytes(_ e: KeyEntry) -> [UInt8] {
        [((e.page & 0x7f) | (e.sign != 0 ? 0x80 : 0)), e.value]
    }

    /// 反查：设备条目 → token（读回配置用）；查不到返回 nil。
    public static func entryToToken(_ e: KeyEntry) -> String? {
        for (k, v) in entryMap where v == e { return k }
        return nil
    }

    /// 帧内 2 字节 [(page&0x7f)|(sign<<7), value] → 条目。
    public static func entryFromWire(_ pageSign: UInt8, _ value: UInt8) -> KeyEntry {
        KeyEntry(page: pageSign & 0x7f, value: value, sign: (pageSign & 0x80) != 0 ? 1 : 0)
    }

    private static let tokenLabels: [String: String] = [
        "LCtrl": "⌃", "LShift": "⇧", "LOpt": "⌥", "LCmd": "⌘",
        "RCtrl": "右⌃", "RShift": "右⇧", "ROpt": "右⌥", "RCmd": "右⌘",
        "Space": "空格", "Up": "↑", "Down": "↓", "Left": "←", "Right": "→",
        "Backspace": "⌫", "Enter": "⏎", "Tab": "⇥", "CapsLock": "⇪", "Delete": "⌦",
        "VolumeUp": "音量+", "VolumeDown": "音量-", "Mute": "静音",
    ]

    public static func tokenLabel(_ token: String) -> String { tokenLabels[token] ?? token }

    /// token 列表 → 展示字符串，如 "⌘+C"、"右⌥+→"。
    public static func tokensToDisplay(_ tokens: [String]) -> String {
        tokens.map(tokenLabel).joined(separator: "+")
    }
}
