import Foundation

/// What the home-screen widgets show, written by the app into the shared App Group
/// whenever receipts change (WidgetBridge) and read by the widget extension.
/// The widget can't open the synced store itself, so it gets this small copy.
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var store: String
        var endDate: Date
        var symbol: String
    }

    /// Receipts still under warranty, the soonest to end first (at most a handful).
    var items: [Item] = []
    /// Value of everything under warranty in the default currency.
    var value: Double = 0
    var currency: String = "CZK"
    var activeCount: Int = 0

    static let appGroup = "group.cz.zaruky.app"
    private static let key = "widget.snapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Saves and tells whether anything changed, so the widgets reload only then.
    @discardableResult
    func save() -> Bool {
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let data = try? JSONEncoder().encode(self) else { return false }
        if defaults.data(forKey: Self.key) == data { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    /// Whole days from today to the end date, as the app counts them.
    static func daysLeft(until end: Date, from now: Date = Date()) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: end)).day ?? 0
    }

    /// Link that opens a receipt's detail in the app.
    static func url(for id: UUID) -> URL { URL(string: "zaruky://purchase/\(id.uuidString)")! }
}
