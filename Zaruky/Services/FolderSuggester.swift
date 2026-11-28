import Foundation
import FoundationModels

@Generable
struct FolderChoice {
    @Guide(description: "Přesný název jedné složky ze seznamu, nebo prázdný text, pokud se žádná nehodí")
    var folderName: String
}

/// Picks one of the user's own folders for a new receipt. Uses the on-device model when it's
/// available, otherwise matches the product against common category words in the folder names.
/// Returns nil when nothing fits, so the receipt stays without a folder.
enum FolderSuggester {
    static func suggest(product: String, store: String, folders: [String]) async -> String? {
        let names = folders.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !names.isEmpty, !product.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        if case .available = SystemLanguageModel.default.availability,
           let choice = try? await askModel(product: product, store: store, folders: names) {
            let picked = choice.trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = names.first(where: { $0.compare(picked, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                return match
            }
            if picked.isEmpty { return nil }
        }
        return byKeywords(product: product, folders: names)
    }

    private static func askModel(product: String, store: String, folders: [String]) async throws -> String {
        let session = LanguageModelSession(instructions: """
            Třídíš účtenky do složek, které si uživatel sám vytvořil. Vyber jednu složku ze seznamu, \
            kam nákup nejlépe patří. Když se žádná nehodí, vrať prázdný text. Nevymýšlej nové složky.
            """)
        let prompt = """
            Složky: \(folders.joined(separator: ", "))
            Produkt: \(product)
            Obchod: \(store)
            """
        return try await session.respond(to: prompt, generating: FolderChoice.self).content.folderName
    }

    /// Words a folder name may contain, per kind of product (by the product's icon).
    private static let categories: [(symbols: [String], folderWords: [String])] = [
        (["iphone", "laptopcomputer", "desktopcomputer", "ipad", "applewatch", "headphones", "tv",
          "hifispeaker.fill", "camera.fill", "gamecontroller.fill", "printer.fill", "wifi.router.fill"],
         ["elektro", "electronic", "technik", "tech", "počítač", "pocitac", "mobil", "gadget", "computer", "handy", "électr", "electr", "elettr", "eletr", "informati", "telefon"]),
        (["washer.fill", "dishwasher.fill", "refrigerator.fill", "oven.fill", "cup.and.saucer.fill", "fanblades.fill"],
         ["domác", "domac", "home", "household", "spotřebič", "spotrebic", "kuchyň", "kuchyn", "appliance", "byt", "dům", "dum", "haushalt", "küche", "kuche", "wohnung", "haus", "maison", "casa", "hogar", "huis", "cuisine", "cocina", "cucina", "cozinha", "keuken", "ménager", "electrodom", "elettrodom", "eletrodom", "agd", "dom"]),
        (["sofa.fill", "lightbulb.fill"], ["nábytek", "nabytek", "furniture", "domác", "domac", "home", "byt", "dům", "dum", "möbel", "mobel", "haushalt", "wohnung", "meuble", "mueble", "mobili", "móvei", "movei", "meubel", "meble", "nábytok", "maison", "casa", "hogar", "huis", "dom"]),
        (["car.fill"], ["auto", "car", "vůz", "vuz", "fahrzeug", "wagen", "voiture", "coche", "carro", "samochód", "samochod"]),
        (["bicycle"], ["kolo", "sport", "bike", "outdoor", "fahrrad", "vélo", "velo", "bici", "fiets", "rower", "bicyk"]),
        (["tshirt.fill"], ["oblečení", "obleceni", "móda", "moda", "clothes", "fashion", "boty", "kleidung", "mode", "schuhe", "vêtement", "vetement", "ropa", "abbigliamento", "roupa", "kleding", "ubrani", "odzież", "odziez", "oblečen", "oblecen"]),
        (["hammer.fill"], ["nářadí", "naradi", "dílna", "dilna", "tools", "zahrad", "garden", "garáž", "garaz", "werkzeug", "werkstatt", "garten", "garage", "outil", "herramienta", "attrezz", "ferrament", "gereedschap", "narzędzi", "narzedzi", "náradi", "jardin", "jardín", "giardino", "jardim", "tuin", "ogród", "ogrod"]),
        (["stroller.fill"], ["dět", "det", "kids", "baby", "miminko", "kinder", "kind", "enfant", "bébé", "bebe", "niño", "nino", "bambin", "criança", "crianca", "dzieci", "dziec"]),
    ]

    static func byKeywords(product: String, folders: [String]) -> String? {
        let lowerProduct = product.lowercased()
        // A folder whose name appears in the product name ("iPhone" folder, "Bosch" folder…).
        if let direct = folders.first(where: { $0.count >= 3 && lowerProduct.contains($0.lowercased()) }) {
            return direct
        }
        let symbol = ProductIcon.symbol(for: product)
        guard let category = categories.first(where: { $0.symbols.contains(symbol) }) else { return nil }
        return folders.first { folder in
            let name = folder.lowercased()
            return category.folderWords.contains { name.contains($0) }
        }
    }
}
