import Foundation

/// The app speaks ten languages. Czech, English and German are written next to each other in
/// every `L(cs, en, de)` call; the others come from `Translations`, looked up by the English text.
/// The language follows the phone's preferred languages (including the per-app language in
/// iOS Settings); a language the app doesn't have falls back to English.
enum L10n {
    enum Language: String, CaseIterable {
        case cs, en, de, sk, pl, fr, es, it, pt, nl

        /// Region used for dates and numbers when the phone's own region doesn't fit.
        var defaultRegion: String {
            switch self {
            case .cs: "CZ"
            case .en: "GB"
            case .de: "DE"
            case .sk: "SK"
            case .pl: "PL"
            case .fr: "FR"
            case .es: "ES"
            case .it: "IT"
            case .pt: "BR"
            case .nl: "NL"
            }
        }
    }

    static let language: Language = {
        for preferred in Locale.preferredLanguages {
            let code = Locale(identifier: preferred).language.languageCode?.identifier
                ?? String(preferred.prefix(2))
            if let match = Language(rawValue: code.lowercased()) { return match }
        }
        return .en
    }()

    static var isEnglish: Bool { language == .en }
    static var isGerman: Bool { language == .de }
    static var isCzech: Bool { language == .cs }

    /// The app language with the phone's region, e.g. fr_BE, en_US, pt_PT. Dates and prices use it.
    static let locale: Locale = {
        let region = Locale.current.region?.identifier ?? language.defaultRegion
        return Locale(identifier: "\(language.rawValue)_\(region)")
    }()
}

/// English text written as a literal, possibly with interpolations. It keeps the text with
/// `%1`, `%2`… in place of the values, so other languages can look the sentence up and put
/// the values back in their own word order.
struct LText: ExpressibleByStringInterpolation {
    typealias StringInterpolation = Interpolation

    let key: String
    let values: [String]

    init(stringLiteral value: String) {
        key = value
        values = []
    }

    init(stringInterpolation: Interpolation) {
        key = stringInterpolation.key
        values = stringInterpolation.values
    }

    struct Interpolation: StringInterpolationProtocol {
        var key = ""
        var values: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {}

        mutating func appendLiteral(_ literal: String) { key += literal }

        mutating func appendInterpolation<T>(_ value: T) {
            values.append("\(value)")
            key += "%\(values.count)"
        }
    }

    /// Puts the values into a template that uses `%1`, `%2`…
    func filling(_ template: String) -> String {
        var text = template
        for (index, value) in values.enumerated().reversed() {
            text = text.replacingOccurrences(of: "%\(index + 1)", with: value)
        }
        return text
    }

    var english: String { filling(key) }
}

/// Picks the text for the current app language: Czech, English or German as written,
/// other languages from `Translations` (English when a sentence is missing there).
func L(_ cs: String, _ en: LText, _ de: String) -> String {
    switch L10n.language {
    case .cs: return cs
    case .en: return en.english
    case .de: return de
    default:
        guard let template = Translations.table(for: L10n.language)[en.key] else { return en.english }
        return en.filling(template)
    }
}
