import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
import UserNotifications
import VibeKitHost

/// Process-owned: closing System Settings or the main window never stops polling.
@MainActor
final class PermissionCenter: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PermissionCenter()
    @Published private(set) var accessibility = false
    @Published private(set) var microphone = false
    @Published private(set) var notifications = false
    @Published private(set) var checked = false
    @Published private(set) var restarting = false
    @Published var error: LocalizedMessage?
    @Published var shouldOpenMain = false
    var authorizationReady: (() -> Void)?
    static let reopenKey = "permissions.openMainAfterRestart"
    private var window: NSWindow?
    private var timer: Timer?
    private var querying = false
    private var completion = PermissionCompletion()
    private let accessibilityProbe = DialPermissionProbe()
    private let microphoneProbe = DialPermissionProbe()
    private var accessibilityProbed = false
    private var microphoneProbed = false
    private var freshAccessibility: Bool?
    private var freshMicrophone: Bool?
    private var nextProbe: TimeInterval = 0
    private var requesting = false
    var allGranted: Bool { checked && accessibility && microphone && notifications }

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        guard !querying, !restarting else { return }
        querying = true
        let now = ProcessInfo.processInfo.systemUptime
        if now >= nextProbe {
            nextProbe = now + (allGranted ? 30 : 3)
            accessibilityProbe.check { [weak self] value in
                self?.freshAccessibility = value
                self?.accessibilityProbed = true
            }
            microphoneProbe.check(argument: DialPermissionProbe.microphoneArgument) { [weak self] value in
                self?.freshMicrophone = value
                self?.microphoneProbed = true
            }
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let allowed = settings.authorizationStatus == .authorized && settings.alertSetting == .enabled
            Task { @MainActor in
                guard let self else { return }
                self.querying = false
                // Establish the launch baseline from fresh results before deciding a
                // permission was newly granted; stale parent APIs must not cause a loop.
                guard self.accessibilityProbed, self.microphoneProbed else { return }
                let wasGranted = self.allGranted
                self.accessibility = PermissionEvidence.granted(current: AXIsProcessTrusted(), fresh: self.freshAccessibility)
                self.microphone = PermissionEvidence.granted(
                    current: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                    fresh: self.freshMicrophone)
                self.notifications = allowed
                let firstCheck = !self.checked
                self.checked = true
                let shouldRestart = self.completion.observe(allGranted: self.allGranted)
                if !self.allGranted {
                    if firstCheck || wasGranted { self.present() }
                } else if shouldRestart {
                    if AXIsProcessTrusted(), DialSingleAction.canPost,
                       AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                        self.finishAuthorization()
                    } else {
                        self.restarting = true
                        UserDefaults.standard.set(true, forKey: Self.reopenKey)
                        // Hide the gate before termination. Its close veto must not
                        // obstruct the app's restart; failures restore the window.
                        self.window?.orderOut(nil)
                        AppLifecycle.requestRestart()
                    }
                } else if self.allGranted, UserDefaults.standard.bool(forKey: Self.reopenKey) {
                    self.finishAuthorization()
                }
                self.window?.standardWindowButton(.closeButton)?.isEnabled = self.allGranted && !self.restarting
            }
        }
    }

    private func finishAuthorization() {
        restarting = false
        authorizationReady?()
        window?.close()
        UserDefaults.standard.removeObject(forKey: Self.reopenKey)
        shouldOpenMain = true
    }

    func restartCancelled() {
        guard restarting else { return }
        restarting = false
        UserDefaults.standard.removeObject(forKey: Self.reopenKey)
        error = LocalizedMessage("自动重启未完成，请退出后重新打开 App。")
        present()
    }

    func presentIfNeeded() {
        nextProbe = 0
        if !allGranted { present() }
        refresh()
    }

    func present() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = L("权限检查")
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: PermissionView(center: self))
            panel.center()
            window = panel
        }
        window?.standardWindowButton(.closeButton)?.isEnabled = allGranted && !restarting
        window?.title = L("权限检查")
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { allGranted && !restarting }
    func refreshLanguage() { window?.title = L("权限检查") }
    func close() { if allGranted && !restarting { finishAuthorization() } }

    // Called only by the user's Settings buttons, never by the polling loop.
    func configure(_ permission: String) {
        guard !requesting else { return }
        error = nil
        switch permission {
        case "accessibility":
            DialSingleAction.requestPermission()
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case "microphone":
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                requesting = true
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                    Task { @MainActor in
                        self?.requesting = false
                        self?.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                        self?.refresh()
                    }
                }
            } else { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") }
        default:
            requesting = true
            ProfileNotifications.shared.requestPermission { [weak self] _ in
                Task { @MainActor in
                    self?.requesting = false
                    self?.open("x-apple.systempreferences:com.apple.preference.notifications")
                    self?.refresh()
                }
            }
        }
    }

    private func open(_ address: String) {
        guard let url = URL(string: address), NSWorkspace.shared.open(url) else {
            error = LocalizedMessage("无法打开系统设置，请按上方路径手动前往。")
            return
        }
    }
}

private struct PermissionView: View {
    @ObservedObject var center: PermissionCenter
    @ObservedObject private var language = AppLanguage.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("权限检查")).font(.title2.bold())
            Text(L("请点击设置完成以下授权。状态会自动更新，全部通过后才能关闭此窗口。"))
                .font(.callout).foregroundStyle(.secondary)
            row("辅助功能", detail: "隐私与安全性 → 辅助功能：用于旋钮单击与双击识别。", granted: center.accessibility, id: "accessibility")
            row("麦克风", detail: "隐私与安全性 → 麦克风：用于麦克风电平测试。", granted: center.microphone, id: "microphone")
            row("通知", detail: "通知 → 当前 App：允许通知，用于提示配置切换结果。", granted: center.notifications, id: "notifications")
            Text(L(center.restarting ? "权限已全部开启，正在重启 App…" : "授权完成后自动打开主页面；必要时会重启 App。"))
                .font(.caption).foregroundStyle(.secondary)
            if let error = center.error { Text(error.rendered()).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(L("退出 App")) { NSApp.terminate(nil) }
                Spacer()
                Button(L("完成")) { center.close() }.disabled(!center.allGranted || center.restarting)
            }
        }.padding(24).frame(width: 520)
            .environment(\.locale, language.locale)
            .onChange(of: language.resolved) { _ in center.refreshLanguage() }
    }
    private func row(_ title: String, detail: String, granted: Bool, id: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .accessibilityLabel(L(granted ? "已授权" : "待授权"))
            VStack(alignment: .leading, spacing: 4) {
                Text(L(title)).font(.headline)
                Text(L(detail)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("设置")) { center.configure(id) }.disabled(center.restarting)
        }
    }
}
