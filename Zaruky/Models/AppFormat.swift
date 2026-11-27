import Foundation

/// Formatting for counts, dates and prices in the app language (Czech or English).
enum AppFormat {
    /// Picks the Czech plural form: 1 den, 2–4 dny, 5+ dní.
    static func czechPlural(_ n: Int, one: String, few: String, many: String) -> String {
        let a = abs(n)
        if a == 1 { return one }
        if (2...4).contains(a) { return few }
        return many
    }

    static func days(_ n: Int) -> String {
        if L10n.isEnglish { return n == 1 ? "1 day" : "\(n) days" }
        return "\(n) " + czechPlural(n, one: "den", few: "dny", many: "dní")
    }

    static func months(_ n: Int) -> String {
        if L10n.isEnglish { return n == 1 ? "1 month" : "\(n) months" }
        return "\(n) " + czechPlural(n, one: "měsíc", few: "měsíce", many: "měsíců")
    }

    static func years(_ n: Int) -> String {
        if L10n.isEnglish { return n == 1 ? "1 year" : "\(n) years" }
        return "\(n) " + czechPlural(n, one: "rok", few: "roky", many: "let")
    }

    static func receipts(_ n: Int) -> String {
        if L10n.isEnglish { return n == 1 ? "1 receipt" : "\(n) receipts" }
        return "\(n) " + czechPlural(n, one: "účtenka", few: "účtenky", many: "účtenek")
    }

    /// Short badge text for remaining warranty, e.g. "12 dní", "8 months".
    static func remaining(days: Int) -> String {
        if days < 0 { return L("Po záruce", "Expired") }
        if days == 0 { return L("Končí dnes", "Ends today") }
        if days <= 60 { return AppFormat.days(days) }
        let months = days / 30
        if months < 24 { return AppFormat.months(months) }
        return AppFormat.years(months / 12)
    }

    static func warrantyLength(months: Int) -> String {
        if months > 0 && months % 12 == 0 { return years(months / 12) }
        return AppFormat.months(months)
    }

    static func price(_ value: Double?, currency: String = "CZK") -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: currency).locale(L10n.locale))
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(L10n.locale))
    }
}
