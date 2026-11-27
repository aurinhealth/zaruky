import Foundation
import SwiftData

/// Launch arguments used by CI to take App Store style screenshots in the simulator:
/// `-demo` opens an in-memory store with sample receipts (nothing touches iCloud or
/// notifications), `-demoScreen detail|paywall|form|folder|settings|empty` opens that screen.
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
        }
        try? context.save()
    }
}
