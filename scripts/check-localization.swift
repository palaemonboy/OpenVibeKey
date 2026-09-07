// Run with Localization.swift and EnglishStrings.swift using swiftc.
import Foundation

private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}

@main
struct LocalizationChecks {
    static func main() {
        let defaults = MemoryDefaults()
        let chineseSystem = AppLanguage(defaults: defaults, preferredLanguages: { ["zh-Hant-TW", "en-US"] })
        precondition(chineseSystem.choice == .system)
        precondition(chineseSystem.resolved == .chinese)
        precondition(chineseSystem.text("已连接") == "已连接")
        chineseSystem.choice = .english
        precondition(defaults.string(forKey: AppLanguage.preferenceKey) == "en")
        let relaunched = AppLanguage(defaults: defaults, preferredLanguages: { ["zh-CN"] })
        precondition(relaunched.resolved == .english)
        precondition(relaunched.text("已连接") == "Connected")
        relaunched.choice = .chinese
        precondition(AppLanguage(defaults: defaults, preferredLanguages: { ["en-GB"] }).resolved == .chinese)
        relaunched.choice = .system
        precondition(AppLanguage(defaults: defaults, preferredLanguages: { ["en-GB"] }).resolved == .english)
        precondition(AppLanguageChoice.system.resolved(preferredLanguages: ["ja-JP"]) == .english)
        precondition(AppLanguageChoice.system.resolved(preferredLanguages: ["fr", "zh-Hans"]) == .chinese)
        defaults.set("invalid", forKey: AppLanguage.preferenceKey)
        precondition(AppLanguage(defaults: defaults, preferredLanguages: { ["en"] }).choice == .system)
        let message = LocalizedMessage("打开 App：{0}", "工作 {0} 100% $1")
        relaunched.choice = .english
        precondition(message.rendered(using: relaunched) == "Open App: 工作 {0} 100% $1")
        relaunched.choice = .chinese
        precondition(message.rendered(using: relaunched) == "打开 App：工作 {0} 100% $1")
        let pattern = try! NSRegularExpression(pattern: #"\{\d+\}"#)
        for (key, value) in EnglishStrings.values {
            func placeholders(_ string: String) -> [String] {
                pattern.matches(in: string, range: NSRange(string.startIndex..., in: string))
                    .map { (string as NSString).substring(with: $0.range) }.sorted()
            }
            precondition(placeholders(key) == placeholders(value), "Placeholder mismatch: \(key)")
        }
        print("Localization checks passed: system matching, saved choice, fallback, live messages and translation placeholders.")
    }
}
