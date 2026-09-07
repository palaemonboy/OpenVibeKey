// InstalledApps.swift — 枚举已安装 App，供「打开 App」选择器使用。
//
// 只扫常规位置的一级子目录（Apple 自己在系统设置里也是这么干的）。
// 装在非常规位置的 App 由 UI 的「从文件选择…」兜底（app(at:)）。
//
// 刻意不带图标：NSImage 不是 Sendable，塞进模型会把并发问题带到每一处传递点。
// 行视图用 NSWorkspace.shared.icon(forFile:) 现取即可，那是带缓存的。
import AppKit
import Foundation

public struct InstalledApp: Identifiable, Equatable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let url: URL

    public init(bundleID: String, name: String, url: URL) {
        self.bundleID = bundleID; self.name = name; self.url = url
    }
}

public enum InstalledApps {
    /// 扫描目录。CoreServices 那条是为了捞到访达——它不在 /System/Applications 下。
    private static var searchRoots: [URL] {
        var roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
        ]
        roots.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"))
        return roots
    }

    /// 枚举已安装 App，按名称升序、bundleID 去重（同一个 App 出现在多处时取先扫到的）。
    public static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        var seen: Set<String> = []
        var out: [InstalledApp] = []

        for root in searchRoots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { continue }
            for item in items {
                // 一级子目录也看一眼（/Applications/Adobe XXX/Foo.app 这种）
                if item.pathExtension != "app" {
                    guard let subs = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles]) else { continue }
                    for sub in subs where sub.pathExtension == "app" {
                        if let a = app(at: sub), seen.insert(a.bundleID).inserted { out.append(a) }
                    }
                    continue
                }
                if let a = app(at: item), seen.insert(a.bundleID).inserted { out.append(a) }
            }
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 从一个 .app 路径解析出条目。不是 App（或读不出 bundleID）时返回 nil。
    public static func app(at url: URL) -> InstalledApp? {
        guard url.pathExtension == "app",
              let bundle = Bundle(url: url),
              let bid = bundle.bundleIdentifier, !bid.isEmpty else { return nil }
        // 本地化显示名优先，退回文件名（去掉 .app）。
        // 只砍末尾的 .app 扩展名——不能用 replacingOccurrences(of: ".app", with: "")，
        // 那会把名字中间任何位置出现的 ".app" 子串也一并砍掉（比如「Snapshot.app Manager」会被错误改写）。
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        return InstalledApp(bundleID: bid, name: name.isEmpty ? url.deletingPathExtension().lastPathComponent : name,
                            url: url)
    }
}
