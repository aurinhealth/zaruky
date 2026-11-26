import SwiftUI
import SwiftData

@main
struct ZarukyApp: App {
    @State private var store = PurchaseStore()

    var body: some Scene {
        WindowGroup {
            PurchaseListView()
                .environment(store)
                .task { await NotificationService.requestAuthorization() }
        }
        .modelContainer(for: Purchase.self)
    }
}
