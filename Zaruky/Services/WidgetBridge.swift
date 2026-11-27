import Foundation
import WidgetKit

/// Keeps the home-screen widgets in step with the receipts.
enum WidgetBridge {
    @MainActor
    static func update(with purchases: [Purchase]) {
        guard !DemoMode.isOn else { return }
        let active = purchases.filter { $0.status != .expired }
        let currency = AppSettings.currency
        var snapshot = WidgetSnapshot()
        snapshot.items = active
            .sorted { $0.warrantyEndDate < $1.warrantyEndDate }
            .prefix(6)
            .map { WidgetSnapshot.Item(id: $0.id, name: $0.productName.isEmpty ? L("Bez názvu", "Untitled") : $0.productName,
                                       store: $0.storeName, endDate: $0.warrantyEndDate,
                                       symbol: ProductIcon.symbol(for: $0.productName)) }
        snapshot.value = active.filter { $0.currencyCode == currency }.compactMap(\.price).reduce(0, +)
        snapshot.currency = currency
        snapshot.activeCount = active.count
        if snapshot.save() { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// The id in a `zaruky://purchase/<id>` link from a widget.
    static func purchaseID(from url: URL) -> UUID? {
        guard url.scheme == "zaruky", url.host() == "purchase" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
