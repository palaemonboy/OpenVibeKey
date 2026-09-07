import SwiftUI

struct LanguageMenu: View {
    @ObservedObject private var language = AppLanguage.shared
    var compact = false

    var body: some View {
        Menu {
            Picker(L("语言"), selection: $language.choice) {
                Text(L("跟随系统")).tag(AppLanguageChoice.system)
                Text("中文").tag(AppLanguageChoice.chinese)
                Text("English").tag(AppLanguageChoice.english)
            }
        } label: {
            if compact {
                Image(systemName: "globe").font(.system(size: 15))
            } else {
                Label(L("语言"), systemImage: "globe")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: compact, vertical: true)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
        .help(L("语言"))
        .accessibilityLabel(L("语言"))
    }
}
