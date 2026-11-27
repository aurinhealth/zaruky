import Foundation

/// Formatting for counts, dates and prices in the app language.
enum AppFormat {
    enum Counted { case day, month, year, receipt }

    /// Picks the Czech plural form: 1 den, 2–4 dny, 5+ dní.
    static func czechPlural(_ n: Int, one: String, few: String, many: String) -> String {
        let a = abs(n)
        if a == 1 { return one }
        if (2...4).contains(a) { return few }
        return many
    }

    /// Polish: 1 dzień, 2–4 / 22–24… dni, 5–21 / 25… dni.
    private static func polishPlural(_ n: Int, one: String, few: String, many: String) -> String {
        let a = abs(n)
        if a == 1 { return one }
        if (2...4).contains(a % 10) && !(12...14).contains(a % 100) { return few }
        return many
    }

    /// The word that goes after a number, e.g. "dny", "months", "Jahre", "jours".
    static func word(_ n: Int, _ unit: Counted) -> String {
        let one = abs(n) == 1
        func pair(_ s: String, _ p: String) -> String { one ? s : p }
        switch L10n.language {
        case .cs:
            switch unit {
            case .day: return czechPlural(n, one: "den", few: "dny", many: "dní")
            case .month: return czechPlural(n, one: "měsíc", few: "měsíce", many: "měsíců")
            case .year: return czechPlural(n, one: "rok", few: "roky", many: "let")
            case .receipt: return czechPlural(n, one: "účtenka", few: "účtenky", many: "účtenek")
            }
        case .sk:
            switch unit {
            case .day: return czechPlural(n, one: "deň", few: "dni", many: "dní")
            case .month: return czechPlural(n, one: "mesiac", few: "mesiace", many: "mesiacov")
            case .year: return czechPlural(n, one: "rok", few: "roky", many: "rokov")
            case .receipt: return czechPlural(n, one: "bloček", few: "bločky", many: "bločkov")
            }
        case .pl:
            switch unit {
            case .day: return polishPlural(n, one: "dzień", few: "dni", many: "dni")
            case .month: return polishPlural(n, one: "miesiąc", few: "miesiące", many: "miesięcy")
            case .year: return polishPlural(n, one: "rok", few: "lata", many: "lat")
            case .receipt: return polishPlural(n, one: "paragon", few: "paragony", many: "paragonów")
            }
        case .en:
            switch unit {
            case .day: return pair("day", "days")
            case .month: return pair("month", "months")
            case .year: return pair("year", "years")
            case .receipt: return pair("receipt", "receipts")
            }
        case .de:
            switch unit {
            case .day: return pair("Tag", "Tage")
            case .month: return pair("Monat", "Monate")
            case .year: return pair("Jahr", "Jahre")
            case .receipt: return pair("Beleg", "Belege")
            }
        case .fr:
            let single = abs(n) <= 1
            switch unit {
            case .day: return single ? "jour" : "jours"
            case .month: return "mois"
            case .year: return single ? "an" : "ans"
            case .receipt: return single ? "ticket" : "tickets"
            }
        case .es:
            switch unit {
            case .day: return pair("día", "días")
            case .month: return pair("mes", "meses")
            case .year: return pair("año", "años")
            case .receipt: return pair("recibo", "recibos")
            }
        case .it:
            switch unit {
            case .day: return pair("giorno", "giorni")
            case .month: return pair("mese", "mesi")
            case .year: return pair("anno", "anni")
            case .receipt: return pair("scontrino", "scontrini")
            }
        case .pt:
            switch unit {
            case .day: return pair("dia", "dias")
            case .month: return pair("mês", "meses")
            case .year: return pair("ano", "anos")
            case .receipt: return pair("recibo", "recibos")
            }
        case .nl:
            switch unit {
            case .day: return pair("dag", "dagen")
            case .month: return pair("maand", "maanden")
            case .year: return "jaar"
            case .receipt: return pair("bon", "bonnen")
            }
        }
    }

    static func days(_ n: Int) -> String { "\(n) " + word(n, .day) }
    static func months(_ n: Int) -> String { "\(n) " + word(n, .month) }
    static func years(_ n: Int) -> String { "\(n) " + word(n, .year) }
    static func receipts(_ n: Int) -> String { "\(n) " + word(n, .receipt) }

    /// Short badge text for remaining warranty, e.g. "12 dní", "8 months".
    static func remaining(days: Int) -> String {
        if days < 0 { return L("Po záruce", "Expired", "Abgelaufen") }
        if days == 0 { return L("Končí dnes", "Ends today", "Endet heute") }
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
        let whole = value.rounded() == value
        return value.formatted(.currency(code: currency).precision(.fractionLength(whole ? 0 : 2)).locale(L10n.locale))
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(L10n.locale))
    }
}
