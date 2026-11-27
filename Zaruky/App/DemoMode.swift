import Foundation
import SwiftData
import UIKit

/// Launch arguments used by CI to take App Store style screenshots in the simulator:
/// `-demo` opens an in-memory store with sample receipts (nothing touches iCloud or
/// notifications), `-demoScreen detail|paywall|form|folder|settings|viewer|empty` opens that screen.
enum DemoMode {
    static let isOn = ProcessInfo.processInfo.arguments.contains("-demo")

    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard isOn, let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func makeContainer(schema: Schema) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: config)
        if screen != "empty" { seed(container.mainContext) }
        return container
    }

    @MainActor
    private static func seed(_ context: ModelContext) {
        let cal = Calendar.current
        func ago(months: Int, days: Int = 0) -> Date {
            let d = cal.date(byAdding: .month, value: -months, to: Date()) ?? Date()
            return cal.date(byAdding: .day, value: -days, to: d) ?? d
        }
        let en = L10n.isEnglish
        let electronics = Folder(name: en ? "Electronics" : "Elektronika")
        let home = Folder(name: en ? "Home" : "Domácnost")
        context.insert(electronics)
        context.insert(home)

        let items: [(String, String, Date, Double, Int, Folder?)] = [
            ("iPhone 16 Pro", "Alza.cz", ago(months: 23, days: 12), 32_990, 24, electronics),
            (en ? "Bosch washing machine" : "Pračka Bosch Serie 6", "Datart", ago(months: 4), 14_490, 36, home),
            ("MacBook Air M4", "iStyle", ago(months: 7), 29_990, 24, electronics),
            ("Sony WH-1000XM6", "Alza.cz", ago(months: 23, days: 2), 9_490, 24, electronics),
            (en ? "De'Longhi coffee machine" : "Kávovar De'Longhi Magnifica", "Mall.cz", ago(months: 14), 11_990, 24, home),
            ("Dyson V15", "Electro World", ago(months: 30), 17_990, 24, home),
        ]
        for (name, store, date, price, months, folder) in items {
            let p = Purchase(productName: name, storeName: store, purchaseDate: date,
                             price: price, warrantyMonths: months, folder: folder)
            context.insert(p)
            if name.hasPrefix("Sony") {
                p.serialNumber = "S01-5824736-B"
                let card = Attachment(kind: .warrantyCard, imageData: sampleWarrantyCard.jpegData(compressionQuality: 0.8))
                context.insert(card)
                card.purchase = p
            }
            if name.hasPrefix("iPhone") { p.serialNumber = "F2LXK9QWN1" }
        }
        try? context.save()
    }

    /// A small warranty card for the detail screenshot.
    static var sampleWarrantyCard: UIImage {
        let size = CGSize(width: 900, height: 620)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.97, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let big: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 52), .foregroundColor: UIColor.black]
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 30), .foregroundColor: UIColor.darkGray]
            NSAttributedString(string: L10n.isEnglish ? "WARRANTY CARD" : "ZÁRUČNÍ LIST", attributes: big).draw(at: CGPoint(x: 60, y: 60))
            for (i, line) in ["Sony WH-1000XM6", "S/N: S01-5824736-B", L10n.isEnglish ? "Warranty: 24 months" : "Záruka: 24 měsíců"].enumerated() {
                NSAttributedString(string: line, attributes: body).draw(at: CGPoint(x: 60, y: 190 + CGFloat(i) * 60))
            }
            UIColor.gray.setStroke()
            ctx.stroke(CGRect(x: 30, y: 30, width: size.width - 60, height: size.height - 60))
        }
    }

    /// A tall A4-like invoice picture for the `viewer` screenshot (same size as an imported PDF page).
    static var sampleInvoice: UIImage {
        let size = CGSize(width: 1240, height: 1754)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let big: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 64), .foregroundColor: UIColor.black]
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 30), .foregroundColor: UIColor.black]
            NSAttributedString(string: "FAKTURA – DAŇOVÝ DOKLAD", attributes: big).draw(at: CGPoint(x: 80, y: 90))
            UIColor.black.setStroke()
            for (i, line) in ["Alza.cz a.s., Jankovcova 1522/53, Praha 7", "Datum vystavení: 20.12.2024",
                              "Apple Mac mini M4 10/10C 16/256GB       1 ks       17 490,00 Kč",
                              "Celkem k úhradě                                    17 490,00 Kč",
                              "Záruka 24 měsíců"].enumerated() {
                NSAttributedString(string: line, attributes: body).draw(at: CGPoint(x: 80, y: 260 + CGFloat(i) * 70))
            }
            ctx.stroke(CGRect(x: 60, y: 220, width: size.width - 120, height: size.height - 300))
        }
    }
}
