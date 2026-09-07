import Foundation
import Combine

// Display language is independent of device settings and persisted profile identifiers.
enum AppLanguageChoice: String, CaseIterable {
    case system, chinese = "zh", english = "en"

    func resolved(preferredLanguages: [String]) -> AppLanguageChoice {
        guard self == .system else { return self }
        for identifier in preferredLanguages {
            let language = identifier.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first
            if language == "zh" { return .chinese }
            if language == "en" { return .english }
        }
        return .english
    }
}

final class AppLanguage: ObservableObject {
    static let preferenceKey = "uiLanguage"
    static let shared = AppLanguage()
    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]

    @Published var choice: AppLanguageChoice {
        didSet { defaults.set(choice.rawValue, forKey: Self.preferenceKey) }
    }

    init(defaults: UserDefaults = .standard, preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
        choice = defaults.string(forKey: Self.preferenceKey).flatMap(AppLanguageChoice.init(rawValue:)) ?? .system
    }

    var resolved: AppLanguageChoice { choice.resolved(preferredLanguages: preferredLanguages()) }
    var locale: Locale { Locale(identifier: resolved == .chinese ? "zh-Hans" : "en") }

    func text(_ key: String, arguments: [String] = []) -> String {
        let template = resolved == .chinese ? key : (EnglishStrings.values[key] ?? key)
        // Replace placeholders in one pass: names containing {0}, %, or $ remain verbatim.
        let source = template as NSString
        var result = ""
        var cursor = 0
        for match in Self.placeholder.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let index = Int(source.substring(with: match.range(at: 1)))!
            result += index < arguments.count ? arguments[index] : source.substring(with: match.range)
            cursor = NSMaxRange(match.range)
        }
        result += source.substring(from: cursor)
        return result
    }

    private static let placeholder = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
}

func L(_ key: String, _ arguments: String...) -> String {
    AppLanguage.shared.text(key, arguments: arguments)
}

/// Stores message keys and arguments, so an existing status can be translated after switching languages.
struct LocalizedMessage {
    struct Part {
        let key: String
        let arguments: [String]
    }
    private var parts: [Part]

    init(_ key: String, _ arguments: String...) {
        parts = [Part(key: key, arguments: arguments)]
    }

    func rendered(using language: AppLanguage = .shared) -> String {
        parts.map { language.text($0.key, arguments: $0.arguments) }.joined(separator: " ")
    }

    static func + (lhs: LocalizedMessage, rhs: LocalizedMessage) -> LocalizedMessage {
        var result = lhs
        result.parts += rhs.parts
        return result
    }
}

