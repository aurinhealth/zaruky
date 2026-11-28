import Foundation

/// Texts for the languages that aren't written inline in `L(cs, en, de)`, keyed by the English
/// text with `%1`, `%2`… in place of interpolated values. One file per language.
enum Translations {
    static func table(for language: L10n.Language) -> [String: String] {
        switch language {
        case .sk: sk
        case .pl: pl
        case .fr: fr
        case .es: es
        case .it: it
        case .pt: pt
        case .nl: nl
        case .cs, .en, .de: [:]
        }
    }
}
