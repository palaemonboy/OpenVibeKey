import Foundation

/// Tracks authorization recovery independently of any window's lifetime.
public struct DialPermissionFlow {
    public enum Phase: Equatable { case idle, waiting, restartRequired }
    public enum Effect: Equatable { case none, requestPermission, promptRestart, enable }
    public private(set) var phase: Phase = .idle
    public init() {}

    public mutating func request(trusted: Bool, canPost: Bool) -> Effect {
        if phase == .restartRequired { return .promptRestart }
        if trusted && canPost { phase = .idle; return .enable }
        phase = .waiting
        if trusted { phase = .restartRequired; return .promptRestart }
        return .requestPermission
    }

    public mutating func observe(trusted: Bool) -> Effect {
        guard phase == .waiting, trusted else { return .none }
        phase = .restartRequired
        return .promptRestart
    }

    public mutating func resume(pending: Bool, trusted: Bool, canPost: Bool) -> Effect {
        guard pending else { return .none }
        return request(trusted: trusted, canPost: canPost)
    }

    public mutating func cancel() { phase = .idle }
}
