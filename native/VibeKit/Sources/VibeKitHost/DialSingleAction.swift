import AppKit
import ApplicationServices
import Carbon.HIToolbox
import IOKit.hidsystem
import VibeKitCore

/// Replays only the dial's configured single action after the double-click deadline.
/// No events are posted by validation/tests; creating an event and posting it are separate.
public enum DialSingleAction {
    public enum Failure: Error { case permission, unsupported, eventCreation }
    public static var accessibilityTrusted: Bool { AXIsProcessTrusted() }
    public static var canPost: Bool { CGPreflightPostEventAccess() }
    public static func requestPermission() { _ = CGRequestPostEventAccess() }

    public static let mediaCodes: [String: Int] = [
        "Media:VolumeUp": Int(NX_KEYTYPE_SOUND_UP), "Media:VolumeDown": Int(NX_KEYTYPE_SOUND_DOWN),
        "Media:Mute": Int(NX_KEYTYPE_MUTE), "Media:PlayPause": Int(NX_KEYTYPE_PLAY),
        "Media:Next": Int(NX_KEYTYPE_NEXT), "Media:Prev": Int(NX_KEYTYPE_PREVIOUS)
    ]
    public static let keyCodes: [String: CGKeyCode] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
        "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "O": 31, "U": 32, "[": 33,
        "I": 34, "P": 35, "Enter": 36, "L": 37, "J": 38, "'": 39, "K": 40, ";": 41,
        "\\": 42, ",": 43, "/": 44, "N": 45, "M": 46, ".": 47, "Tab": 48,
        "Space": 49, "`": 50, "Backspace": 51, "Esc": 53, "RCmd": 54, "LCmd": 55,
        "LShift": 56, "CapsLock": 57, "LOpt": 58, "LCtrl": 59, "RShift": 60, "ROpt": 61, "RCtrl": 62,
        "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97,
        "F7": 98, "F8": 100, "F9": 101, "F10": 109, "F11": 103, "F12": 111,
        "Home": 115, "End": 119, "PageUp": 116, "PageDown": 121, "Delete": 117,
        "Left": 123, "Right": 124, "Down": 125, "Up": 126
    ]
    private static func flag(_ token: String) -> CGEventFlags {
        switch token {
        case "LCmd", "RCmd": return .maskCommand
        case "LOpt", "ROpt": return .maskAlternate
        case "LCtrl", "RCtrl": return .maskControl
        case "LShift", "RShift": return .maskShift
        default: return []
        }
    }
    public static func supports(_ tokens: [String]) -> Bool {
        tokens.isEmpty || (tokens.count == 1 && mediaCodes[tokens[0]] != nil)
            || (tokens.allSatisfy { keyCodes[$0] != nil } && tokens.count <= 4)
    }
    public static func events(for tokens: [String]) throws -> [CGEvent] {
        guard supports(tokens) else { throw Failure.unsupported }
        if tokens.count == 1, let code = mediaCodes[tokens[0]] {
            return try [true, false].map { down in
                let state = Int(down ? NX_KEYDOWN : NX_KEYUP)
                guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                    modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)), timestamp: 0, windowNumber: 0, context: nil,
                    subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS), data1: (code << 16) | (state << 8), data2: -1)?.cgEvent
                else { throw Failure.eventCreation }
                return event
            }
        }
        let source = CGEventSource(stateID: .privateState)
        var flags: CGEventFlags = []
        var result: [CGEvent] = []
        let ordered = tokens.filter { VibeKitKeymap.isModifierToken($0) }
            + tokens.filter { !VibeKitKeymap.isModifierToken($0) }
        for token in ordered {
            flags.formUnion(flag(token))
            guard let code = keyCodes[token], let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
            else { throw Failure.eventCreation }
            event.flags = flags; result.append(event)
        }
        for token in ordered.reversed() {
            flags.subtract(flag(token))
            guard let code = keyCodes[token], let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
            else { throw Failure.eventCreation }
            event.flags = flags; result.append(event)
        }
        return result
    }
    public static func perform(_ tokens: [String]) throws {
        guard !tokens.isEmpty else { return }
        guard canPost else { throw Failure.permission }
        for event in try events(for: tokens) { event.post(tap: .cghidEventTap) }
    }
}
