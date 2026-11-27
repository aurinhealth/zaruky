import Foundation
import FoundationModels

/// Data pulled out of a receipt, used to prefill the form.
struct ReceiptDraft {
    var storeName: String = ""
    var productName: String = ""
    var purchaseDate: Date?
    var price: Double?
    /// nil when the receipt doesn't say; the form then uses the default from Settings.
    var warrantyMonths: Int?
    /// The receipt shows a warranty bought on top of the legal one (e.g. Alza's "Prodloužená záruka +3 roky").
    var extendedWarranty: Bool = false
    /// "S/N: …" or "IMEI: …" printed on the receipt.
    var serialNumber: String?
    var usedAI: Bool = false
}

@Generable
struct ReceiptExtraction {
    @Guide(description: "Název obchodu nebo prodejce, např. Alza, Datart, IKEA")
    var storeName: String

    @Guide(description: "Název hlavního zakoupeného produktu, stručně, např. iPhone 16 128 GB")
    var productName: String

    @Guide(description: "Datum nákupu ve formátu RRRR-MM-DD, nebo prázdný text, pokud datum chybí")
    var purchaseDate: String

    @Guide(description: "Celková zaplacená cena jako číslo bez měny, 0 pokud není známa")
    var totalPrice: Double

    @Guide(description: "Celková délka záruky v měsících, včetně prodloužené záruky koupené navíc (např. zákonných 24 měsíců + prodloužená záruka o 3 roky = 60). Pokud není na účtence uvedena, 24.")
    var warrantyMonths: Int

    @Guide(description: "true, pokud účtenka obsahuje prodlouženou nebo rozšířenou záruku (např. položka „Prodloužená záruka“, „+1 rok záruky“, „Záruka 5 let“), jinak false")
    var hasExtendedWarranty: Bool
}

enum ReceiptParser {
    static func parse(_ text: String) async -> ReceiptDraft {
        let fallback = parseWithRules(text)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fallback }

        if case .available = SystemLanguageModel.default.availability {
            if let ai = try? await parseWithModel(text) {
                var draft = ReceiptDraft(usedAI: true)
                draft.storeName = ai.storeName.isEmpty ? fallback.storeName : ai.storeName
                draft.productName = ai.productName
                draft.purchaseDate = isoDate(ai.purchaseDate) ?? fallback.purchaseDate
                draft.price = ai.totalPrice > 0 ? ai.totalPrice : fallback.price
                draft.serialNumber = fallback.serialNumber
                draft.warrantyMonths = fallback.warrantyMonths
                draft.extendedWarranty = fallback.extendedWarranty
                // The rules read the receipt's own words, so they win. The model answers 24 when the
                // receipt says nothing, so its 24 doesn't count; past 24 it must say it saw an extension.
                let aiMonths = (1...240).contains(ai.warrantyMonths) ? ai.warrantyMonths : nil
                if fallback.warrantyMonths == nil, let aiMonths, aiMonths != 24 {
                    if aiMonths < 24 || ai.hasExtendedWarranty {
                        draft.warrantyMonths = aiMonths
                        draft.extendedWarranty = aiMonths > 24
                    }
                }
                return draft
            }
        }
        return fallback
    }

    private static func parseWithModel(_ text: String) async throws -> ReceiptExtraction {
        let session = LanguageModelSession(instructions: """
            Jsi asistent, který z textu účtenky (přečteného OCR, může obsahovat chyby) \
            vytáhne údaje o nákupu. Odpovídej jen údaji z účtenky, nic si nevymýšlej.
            """)
        let prompt = "Text účtenky:\n\(text.prefix(4000))"
        let response = try await session.respond(to: prompt, generating: ReceiptExtraction.self)
        return response.content
    }

    // MARK: - Rule-based fallback

    static func parseWithRules(_ text: String) -> ReceiptDraft {
        var draft = ReceiptDraft()
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        draft.storeName = lines.first ?? ""
        draft.purchaseDate = firstDate(in: text)
        draft.price = totalPrice(in: lines)
        draft.serialNumber = serialNumber(in: text)
        if let warranty = warranty(in: text) {
            draft.warrantyMonths = warranty.months
            draft.extendedWarranty = warranty.extended
        }
        return draft
    }

    private static func isoDate(_ string: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string.trimmingCharacters(in: .whitespaces))
    }

    private static func firstDate(in text: String) -> Date? {
        let pattern = #"(\d{1,2})\.\s?(\d{1,2})\.\s?(\d{2,4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let d = Int(ns.substring(with: match.range(at: 1))),
                  let m = Int(ns.substring(with: match.range(at: 2))),
                  var y = Int(ns.substring(with: match.range(at: 3))) else { continue }
            if y < 100 { y += 2000 }
            var comps = DateComponents()
            comps.day = d; comps.month = m; comps.year = y
            if (1...31).contains(d), (1...12).contains(m), (2000...2100).contains(y),
               let date = Calendar.current.date(from: comps), date <= Date() {
                return date
            }
        }
        return nil
    }

    private static func totalPrice(in lines: [String]) -> Double? {
        let keywords = ["celkem", "k úhradě", "k uhrade", "total", "suma", "zaplaceno",
                        "summe", "gesamt", "zu zahlen"]
        for line in lines {
            let lower = line.lowercased()
            if keywords.contains(where: { lower.contains($0) }), let value = lastNumber(in: line) {
                return value
            }
        }
        return nil
    }

    private static func lastNumber(in line: String) -> Double? {
        let pattern = #"(\d{1,3}(?:[  ]\d{3})*|\d+)(?:[.,](\d{1,2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let match = regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        let whole = ns.substring(with: match.range(at: 1))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        var number = whole
        if match.range(at: 2).location != NSNotFound {
            number += "." + ns.substring(with: match.range(at: 2))
        }
        return Double(number)
    }

    /// "S/N: C02XK1ABJG5J", "Sériové číslo: …", "IMEI 356789012345678".
    static func serialNumber(in text: String) -> String? {
        let pattern = #"(?<![\p{L}\d])(?:S/N|SN|sériové číslo|seriove cislo|výrobní číslo|vyrobni cislo|serial(?: number| no\.?)?|seriennummer|serien-nr\.?|IMEI)\s*[:#.]?\s*([A-Z0-9][A-Z0-9-]{4,29})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let value = ns.substring(with: match.range(at: 1))
        // A real serial has digits in it; this skips words like "SN: ANO".
        return value.rangeOfCharacter(from: .decimalDigits) == nil ? nil : value.uppercased()
    }

    /// Units after a number: months or years, Czech, English and German.
    private static let unit = #"(měsíc\w*|mesic\w*|měs\.?|mes\.?|m\.|let|roky|rok\w*|years?|yrs?|months?|mo\.?|monat\w*|mon\.?|jahr\w*|j\.)"#

    private static func months(_ n: Int, _ unit: String) -> Int {
        let u = unit.lowercased()
        let years = u.hasPrefix("let") || u.hasPrefix("rok") || u.hasPrefix("year") || u.hasPrefix("yr")
            || u.hasPrefix("jahr") || u == "j."
        return years ? n * 12 : n
    }

    /// Total warranty in months and whether it was extended beyond the legal 24 months.
    /// "Prodloužená záruka o 3 roky" or "+1 rok záruky" add to the legal 24 months;
    /// "Záruka 36 měsíců" or "5 let záruka" is the whole length. The longest one found wins,
    /// since a receipt often lists the legal warranty and the bought extension separately.
    static func warranty(in text: String) -> (months: Int, extended: Bool)? {
        let word = #"(?:záruk|zaruk|garanc|garantie|gewährleist|gewahrleist|warrant)\w*"#
        let extensionWord = #"(?:prodlouž|prodlouz|rozšíř|rozsir|extended|extra|verlänger|verlanger|erweitert)\w*"#
        var found: [Int] = []

        // Added on top: "+3 roky záruky", "prodloužená záruka o 3 roky", "extended warranty +2 years".
        let added = [
            #"\+\s*(\d{1,2})\s*"# + unit + #"\s*(?:\w+\s+)?"# + word,
            extensionWord + #"\s+"# + word + #"\D{0,6}?(?:\+|\bo\b|\bby\b|\bum\b)\s*(\d{1,2})\s*"# + unit,
            word + #"\s*\+\s*(\d{1,2})\s*"# + unit,
        ]
        for pattern in added {
            for (n, u) in matches(pattern, in: text) {
                let total = 24 + months(n, u)
                if (25...240).contains(total) { found.append(total) }
            }
        }

        // The whole length: "Záruka 36 měsíců", "záruka: 2 roky", "5 let záruka".
        let whole = [
            word + #"\D{0,12}?(\d{1,3})\s*"# + unit + #"(?!\w)"#,
            #"(\d{1,2})\s*"# + unit + #"\s+(?:\w+\s+)?"# + word,
        ]
        for pattern in whole {
            for (n, u) in matches(pattern, in: text) {
                let total = months(n, u)
                if (1...240).contains(total) { found.append(total) }
            }
        }

        guard let best = found.max() else { return nil }
        // Past the legal 24 months it's an extension, whether bought or the maker's own.
        return (best, best > 24)
    }

    private static func matches(_ pattern: String, in text: String) -> [(Int, String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.numberOfRanges >= 3, let n = Int(ns.substring(with: m.range(at: 1))) else { return nil }
            return (n, ns.substring(with: m.range(at: 2)))
        }
    }
}
