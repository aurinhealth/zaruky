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
        let demo = DemoData.current
        let electronics = Folder(name: demo.folders.0)
        let home = Folder(name: demo.folders.1)
        context.insert(electronics)
        context.insert(home)

        // Prices are Czech crowns; other languages divide them into their own currency.
        let items: [(String, Int, Date, Double, Int, Folder?)] = [
            ("iPhone 16 Pro", 0, ago(months: 23, days: 12), 32_990, 24, electronics),
            (demo.washer, 1, ago(months: 4), 14_490, 36, home),
            ("MacBook Air M4", 2, ago(months: 7), 29_990, 24, electronics),
            ("Sony WH-1000XM6", 3, ago(months: 23, days: 2), 9_490, 24, electronics),
            (demo.coffee, 4, ago(months: 14), 11_990, 24, home),
            ("Dyson V15", 5, ago(months: 30), 17_990, 24, home),
        ]
        for (name, store, date, price, months, folder) in items {
            let converted = demo.rate == 1 ? price : (price / demo.rate).rounded() - 0.01
            let p = Purchase(productName: name, storeName: demo.stores[store], purchaseDate: date,
                             price: converted, warrantyMonths: months, folder: folder)
            p.currencyCode = demo.currency
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

    /// Sample folders, products, shops and currency for each app language.
    struct DemoData {
        let folders: (String, String)
        let washer: String
        let coffee: String
        let stores: [String]
        let currency: String
        /// Czech crowns per unit of `currency`.
        let rate: Double

        static var current: DemoData {
            switch L10n.language {
            case .cs:
                DemoData(folders: ("Elektronika", "Domácnost"), washer: "Pračka Bosch Serie 6", coffee: "Kávovar De'Longhi Magnifica",
                         stores: ["Alza.cz", "Datart", "iStyle", "Alza.cz", "Mall.cz", "Electro World"], currency: "CZK", rate: 1)
            case .en:
                DemoData(folders: ("Electronics", "Home"), washer: "Bosch washing machine", coffee: "De'Longhi coffee machine",
                         stores: ["Best Buy", "Home Depot", "Apple Store", "Amazon", "Target", "Best Buy"], currency: "USD", rate: 23)
            case .de:
                DemoData(folders: ("Elektronik", "Haushalt"), washer: "Bosch Waschmaschine Serie 6", coffee: "De'Longhi Kaffeevollautomat",
                         stores: ["MediaMarkt", "Saturn", "Apple Store", "MediaMarkt", "Otto", "Amazon"], currency: "EUR", rate: 25)
            case .sk:
                DemoData(folders: ("Elektronika", "Domácnosť"), washer: "Práčka Bosch Serie 6", coffee: "Kávovar De'Longhi Magnifica",
                         stores: ["Alza.sk", "NAY", "iStyle", "Alza.sk", "Datart", "Planeo"], currency: "EUR", rate: 25)
            case .pl:
                DemoData(folders: ("Elektronika", "Dom"), washer: "Pralka Bosch Serie 6", coffee: "Ekspres De'Longhi Magnifica",
                         stores: ["x-kom", "RTV Euro AGD", "iSpot", "Media Expert", "Allegro", "MediaMarkt"], currency: "PLN", rate: 5.8)
            case .fr:
                DemoData(folders: ("Électronique", "Maison"), washer: "Lave-linge Bosch Série 6", coffee: "Expresso De'Longhi Magnifica",
                         stores: ["Fnac", "Darty", "Apple Store", "Boulanger", "Amazon", "Darty"], currency: "EUR", rate: 25)
            case .es:
                DemoData(folders: ("Electrónica", "Hogar"), washer: "Lavadora Bosch Serie 6", coffee: "Cafetera De'Longhi Magnifica",
                         stores: ["MediaMarkt", "El Corte Inglés", "Apple Store", "PcComponentes", "Amazon", "Fnac"], currency: "EUR", rate: 25)
            case .it:
                DemoData(folders: ("Elettronica", "Casa"), washer: "Lavatrice Bosch Serie 6", coffee: "Macchina caffè De'Longhi",
                         stores: ["MediaWorld", "Unieuro", "Apple Store", "Euronics", "Amazon", "MediaWorld"], currency: "EUR", rate: 25)
            case .pt:
                DemoData(folders: ("Eletrônicos", "Casa"), washer: "Lavadora Bosch Serie 6", coffee: "Cafeteira De'Longhi Magnifica",
                         stores: ["Magazine Luiza", "Casas Bahia", "Apple Store", "Fast Shop", "Amazon", "Mercado Livre"], currency: "BRL", rate: 4)
            case .nl:
                DemoData(folders: ("Elektronica", "Huis"), washer: "Bosch wasmachine Serie 6", coffee: "De'Longhi koffiemachine",
                         stores: ["Coolblue", "MediaMarkt", "Apple Store", "bol.com", "Amazon", "Coolblue"], currency: "EUR", rate: 25)
            }
        }
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
            NSAttributedString(string: L("ZÁRUČNÍ LIST", "WARRANTY CARD", "GARANTIESCHEIN"), attributes: big).draw(at: CGPoint(x: 60, y: 60))
            for (i, line) in ["Sony WH-1000XM6", "S/N: S01-5824736-B", L("Záruka: 24 měsíců", "Warranty: 24 months", "Garantie: 24 Monate")].enumerated() {
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
            let (title, lines) = invoiceText
            NSAttributedString(string: title, attributes: big).draw(at: CGPoint(x: 80, y: 90))
            UIColor.black.setStroke()
            for (i, line) in lines.enumerated() {
                NSAttributedString(string: line, attributes: body).draw(at: CGPoint(x: 80, y: 260 + CGFloat(i) * 70))
            }
            ctx.stroke(CGRect(x: 60, y: 220, width: size.width - 120, height: size.height - 300))
        }
    }

    /// Czech invoice for Czech and Slovak, German for German, English for the rest.
    private static var invoiceText: (String, [String]) {
        switch L10n.language {
        case .cs, .sk:
            ("FAKTURA – DAŇOVÝ DOKLAD",
             ["Alza.cz a.s., Jankovcova 1522/53, Praha 7", "Datum vystavení: 20.12.2024",
              "Apple Mac mini M4 10/10C 16/256GB       1 ks       17 490,00 Kč",
              "Celkem k úhradě                                    17 490,00 Kč",
              "Záruka 24 měsíců"])
        case .de:
            ("RECHNUNG",
             ["MediaMarkt, Kaiserstraße 1, Berlin", "Rechnungsdatum: 20.12.2024",
              "Apple Mac mini M4 10/10C 16/256GB       1 Stk.       699,00 €",
              "Gesamtbetrag                                         699,00 €",
              "Garantie 24 Monate"])
        default:
            ("INVOICE",
             ["Apple Store, Fifth Avenue, New York", "Invoice date: 12/20/2024",
              "Apple Mac mini M4 10/10C 16/256GB       1 pc       $599.00",
              "Total                                              $599.00",
              "Warranty 24 months"])
        }
    }
}
