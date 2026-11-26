import Foundation
import FoundationModels

/// Data pulled out of a receipt, used to prefill the form.
struct ReceiptDraft {
    var storeName: String = ""
    var productName: String = ""
    var purchaseDate: Date?
    var price: Double?
    var warrantyMonths: Int = 24
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

    @Guide(description: "Délka záruky v měsících. Pokud není na účtence uvedena, 24.")
    var warrantyMonths: Int
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
                draft.warrantyMonths = (1...240).contains(ai.warrantyMonths) ? ai.warrantyMonths : 24
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
        if let months = warrantyMonths(in: text) { draft.warrantyMonths = months }
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
        let keywords = ["celkem", "k úhradě", "k uhrade", "total", "suma", "zaplaceno"]
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

    private static func warrantyMonths(in text: String) -> Int? {
        let pattern = #"záruk[a-z]*\D{0,10}(\d{1,3})\s*(měs|mes|m\b|let|rok)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let n = Int(ns.substring(with: match.range(at: 1))) else { return nil }
        let unit = ns.substring(with: match.range(at: 2)).lowercased()
        return (unit.hasPrefix("let") || unit.hasPrefix("rok")) ? n * 12 : n
    }
}
