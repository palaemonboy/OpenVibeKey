// AppLauncher.swift — 按 bundleID 激活 App（没运行就启动）。
//
// openApplication(at:configuration:) 一次调用就覆盖两种情况：
// 未运行则启动、已运行则切到最前。不需要自己判断 NSRunningApplication。
import AppKit
import Foundation

public enum AppLauncherError: Error, Equatable {
    /// 按 bundleID 找不到已安装的 App（多半是被卸载了）。
    case notFound(String)
}

public enum AppLauncher {
    /// 激活（必要时启动）指定 App。
    /// 抛 notFound 时调用方应在界面上提示「找不到该 App」并**保留绑定**，供用户改绑。
    public static func activate(bundleID: String) throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw AppLauncherError.notFound(bundleID)
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
    }
}
