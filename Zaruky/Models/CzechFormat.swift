import Foundation

enum CzechFormat {
    /// Picks the Czech plural form: 1 den, 2–4 dny, 5+ dní.
    static func plural(_ n: Int, one: String, few: String, many: String) -> String {
        let a = abs(n)
        if a == 1 { return one }
        if (2...4).contains(a) { return few }
        return many
    }

    static func days(_ n: Int) -> String {
        "\(n) " + plural(n, one: "den", few: "dny", many: "dní")
    }

    static func months(_ n: Int) -> String {
        "\(n) " + plural(n, one: "měsíc", few: "měsíce", many: "měsíců")
    }

    static func years(_ n: Int) -> String {
        "\(n) " + plural(n, one: "rok", few: "roky", many: "let")
    }

    /// Short badge text for remaining warranty, e.g. "12 dní", "8 měsíců".
    static func remaining(days: Int) -> String {
        if days < 0 { return "Po záruce" }
        if days == 0 { return "Končí dnes" }
        if days <= 60 { return CzechFormat.days(days) }
        let months = days / 30
        if months < 24 { return CzechFormat.months(months) }
        return CzechFormat.years(months / 12)
    }

    static func warrantyLength(months: Int) -> String {
        if months > 0 && months % 12 == 0 { return years(months / 12) }
        return CzechFormat.months(months)
    }

    static func price(_ value: Double?, currency: String = "CZK") -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: currency).locale(Locale(identifier: "cs_CZ")))
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "cs_CZ")))
    }
}
