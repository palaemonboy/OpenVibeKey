import Foundation
import ApplicationServices

/// A fresh copy of this executable only checks permission and exits, before creating the VM.
/// This handles systems where the running process keeps an outdated permission result.
final class DialPermissionProbe {
    static let argument = "--check-dial-accessibility"
    static let microphoneArgument = "--check-microphone-permission"
    private var process: Process?

    func check(argument: String = DialPermissionProbe.argument, completion: @escaping (Bool?) -> Void) {
        guard process == nil, let executable = Bundle.main.executableURL,
              Bundle.main.bundleURL.pathExtension == "app" else { completion(nil); return }
        let child = Process()
        child.executableURL = executable
        child.arguments = [argument]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.process === finished else { return }
                self.process = nil
                completion(finished.terminationReason == .exit ? finished.terminationStatus == 0 : nil)
            }
        }
        process = child
        do { try child.run() }
        catch { process = nil; completion(nil); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak child] in
            guard let self, let child, self.process === child, child.isRunning else { return }
            child.terminate()
        }
    }

    func cancel() {
        if let child = process, child.isRunning { child.terminate() }
        process = nil
    }
}
