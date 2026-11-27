import Foundation

/// The app ships in Czech (default), English and German. The language follows the phone's
/// preferred languages; anything else falls back to Czech.
enum L10n {
    enum Language { case cs, en, de }

    static let language: Language = {
        let code = Bundle.main.preferredLocalizations.first ?? "cs"
        if code.hasPrefix("en") { return .en }
        if code.hasPrefix("de") { return .de }
        return .cs
    }()

    static var isEnglish: Bool { language == .en }
    static var isGerman: Bool { language == .de }

    static var locale: Locale {
        switch language {
        case .en: Locale(identifier: "en_GB")
        case .de: Locale(identifier: "de_DE")
        case .cs: Locale(identifier: "cs_CZ")
        }
    }
}

/// Picks the Czech, English or German text for the current app language.
func L(_ cs: String, _ en: String, _ de: String) -> String {
    switch L10n.language {
    case .cs: cs
    case .en: en
    case .de: de
    }
}
