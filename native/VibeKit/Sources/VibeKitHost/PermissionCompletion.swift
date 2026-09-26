/// A process may automatically restart once, after an observed incomplete setup
/// becomes complete. Unknown status must not be interpreted as missing permission.
public struct PermissionCompletion {
    private var sawMissing = false
    private var requestedRestart = false
    public init() {}

    public mutating func observe(allGranted: Bool?) -> Bool {
        guard let allGranted else { return false }
        if !allGranted { sawMissing = true; return false }
        guard sawMissing, !requestedRestart else { return false }
        requestedRestart = true
        return true
    }
}

/// A helper's denial is not authoritative for the running app's TCC identity.
/// A positive live result must never be overwritten by a negative helper result.
public enum PermissionEvidence {
    public static func granted(current: Bool, fresh: Bool?) -> Bool {
        current || fresh == true
    }
}
