// AppPickerSheet.swift — 「打开 App」的目标选择器。
//
// 用 sheet 而不是 popover：列表长、带搜索框，popover 尺寸受限且点外面就关，容易误操作。
// 取消时不回调 onPick，调用方因此什么都不用回滚。
import AppKit
import SwiftUI
import VibeKitHost

struct AppPickerSheet: View {
    @ObservedObject private var language = AppLanguage.shared
    let onPick: (InstalledApp) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var apps: [InstalledApp] = []
    @State private var loading = true

    private var filtered: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.bundleID.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("选择要打开的 App"))
                .font(.system(.headline, design: .rounded))

            TextField(L("搜索名称或 Bundle ID"), text: $query)
                .textFieldStyle(.roundedBorder)

            if loading {
                HStack { ProgressView().controlSize(.small); Text(L("正在枚举…")).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                VStack(spacing: 6) {
                    Text(L("没有匹配的 App")).foregroundStyle(.secondary)
                    Text(L("装在非常规位置的 App 请用下方「从文件选择…」"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { app in
                            AppRow(app: app) { onPick(app); dismiss() }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Divider()
            HStack {
                // 兜底：枚举不到的（装在非常规位置的）App 从这里选
                Button(L("从文件选择…"), action: pickFromFile).buttonStyle(GhostButtonStyle())
                Spacer()
                Button(L("取消")) { dismiss() }.buttonStyle(GhostButtonStyle()).keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 420, height: 460)
        .task {
            // 枚举要走磁盘，别卡住 sheet 的出场动画
            let found = await Task.detached(priority: .userInitiated) { InstalledApps.scan() }.value
            apps = found
            loading = false
        }
    }

    private func pickFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("选择")
        guard panel.runModal() == .OK, let url = panel.url, let app = InstalledApps.app(at: url) else { return }
        onPick(app)
        dismiss()
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            // 图标现取——NSWorkspace 自带缓存，不值得塞进模型换来一堆 Sendable 麻烦
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name).font(.system(.body, design: .rounded))
                Text(app.bundleID).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hover ? Color.accentColor.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
    }
}
