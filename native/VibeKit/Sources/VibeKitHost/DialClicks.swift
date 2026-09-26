import Foundation

/// Monotonic-time state machine. Repeated key-down reports are not extra clicks.
public struct DialClicks {
    public enum Action: Equatable { case single, double }
    public private(set) var deadline: TimeInterval?
    private var down = false
    public init() {}
    public static func validInterval(_ value: Double) -> Bool { value.isFinite && (0.1...1.0).contains(value) }
    public mutating func cancel() { deadline = nil; down = false }
    public mutating func release() { down = false }
    public mutating func press(at now: TimeInterval, interval: TimeInterval) -> [Action] {
        guard !down else { return [] }
        down = true
        if let end = deadline {
            if now <= end { deadline = nil; return [.double] }
            deadline = now + interval
            return [.single]
        }
        deadline = now + interval
        return []
    }
    public mutating func expire(at now: TimeInterval) -> [Action] {
        guard let end = deadline, now >= end else { return [] }
        deadline = nil
        return [.single]
    }
}

/// Carbon treats left/right modifiers alike. Reserve a key unused by any saved single action.
public enum DialCaptureKeys {
    public static func equivalent(_ a: [String], _ b: [String]) -> Bool {
        func normalized(_ tokens: [String]) -> Set<String> {
            Set(tokens.map { ["RCtrl": "LCtrl", "RCmd": "LCmd", "ROpt": "LOpt", "RShift": "LShift"][$0] ?? $0 })
        }
        return normalized(a) == normalized(b)
    }
    public static func candidates(preferred: String?, used: [[String]]) -> [SentinelCombo] {
        let first = SentinelPool.all.filter { $0.mainKey == preferred }
        return (first + SentinelPool.all.filter { $0.mainKey != preferred }).filter { candidate in
            !used.contains { equivalent($0, candidate.tokens) }
        }
    }
}
