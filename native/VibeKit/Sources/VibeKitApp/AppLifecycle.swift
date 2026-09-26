import AppKit

final class AppLifecycle: NSObject, NSApplicationDelegate {
    static var prepareQuit: ((@escaping (Bool) -> Void) -> Void)?
    static var checkPermission: (() -> Void)?
    static var terminationCancelled: (() -> Void)?
    private static var restartRequested = false
    private static var terminationID: UUID?
    private static var relaunchHelper: Process?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppLanguage.shared.refreshSystemLanguage()
        Self.checkPermission?()
    }

    static func requestRestart() {
        restartRequested = true
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.terminationID == nil else { return .terminateLater }
        let attempt = UUID()
        Self.terminationID = attempt
        if Self.restartRequested {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                guard Self.terminationID == attempt else { return }
                Self.finishTermination(sender, allowed: false)
            }
        }
        // Relaunch uses the same verified device-restoration path as normal quit.
        DispatchQueue.main.async {
            guard let prepare = Self.prepareQuit else { Self.finishTermination(sender, allowed: true); return }
            prepare { restored in
                guard Self.terminationID == attempt else { return }
                if restored { Self.finishTermination(sender, allowed: true); return }
                // A user decision must not race the automatic restart timeout.
                Self.terminationID = UUID()
                let alert = NSAlert()
                alert.messageText = L("尚未恢复旋钮的单击设置")
                alert.informativeText = L("设备可能已断开。现在退出后，旋钮按下可能暂时无效；下次连接并启动 App 时会恢复。")
                alert.addButton(withTitle: L("取消退出"))
                alert.addButton(withTitle: L("仍然退出"))
                Self.finishTermination(sender, allowed: alert.runModal() == .alertSecondButtonReturn)
            }
        }
        return .terminateLater
    }

    private static func finishTermination(_ sender: NSApplication, allowed: Bool) {
        terminationID = nil
        guard allowed else {
            restartRequested = false
            terminationCancelled?()
            sender.reply(toApplicationShouldTerminate: false)
            return
        }
        if restartRequested {
            do { try launchAfterExit() }
            catch {
                restartRequested = false
                terminationCancelled?()
                let alert = NSAlert()
                alert.messageText = L("无法自动重启")
                alert.informativeText = L("请退出后手动打开当前版本的 App。")
                alert.runModal()
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
        }
        sender.reply(toApplicationShouldTerminate: true)
    }

    private static func launchAfterExit() throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            throw CocoaError(.executableNotLoadable)
        }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // PID and bundle path are positional arguments, never interpolated shell code.
        // Wait for the old process to exit so two apps cannot write to the device together.
        helper.arguments = ["-c", """
            relaunch_attempts=300
            while /bin/kill -0 "$1" 2>/dev/null; do
                relaunch_attempts=$((relaunch_attempts - 1))
                if [ "$relaunch_attempts" -le 0 ]; then exit 1; fi
                /bin/sleep 0.1
            done
            exec /usr/bin/open -n "$2"
            """, "openvibekey-relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        relaunchHelper = helper
    }
}
