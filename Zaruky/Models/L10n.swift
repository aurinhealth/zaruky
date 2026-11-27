import Foundation

/// The app ships in Czech (default) and English. The language follows the phone's
/// preferred languages; anything other than English falls back to Czech.
enum L10n {
    static let isEnglish: Bool = (Bundle.main.preferredLocalizations.first ?? "cs").hasPrefix("en")

    static var locale: Locale {
        isEnglish ? Locale(identifier: "en_GB") : Locale(identifier: "cs_CZ")
    }
}

/// Picks the Czech or English text for the current app language.
func L(_ cs: String, _ en: String) -> String {
    L10n.isEnglish ? en : cs
}
