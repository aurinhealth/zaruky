import SwiftUI
import SwiftData

@main
struct ZarukyApp: App {
    @State private var store = PurchaseStore()

    /// One store for receipts and folders. `.automatic` syncs through the iCloud
    /// container in the app's entitlements (iCloud.cz.zaruky.app) when the user is
    /// signed in to iCloud, and stays local otherwise. The store file is the same as
    /// before, so receipts saved by earlier versions are kept and uploaded.
    private let container: ModelContainer = {
        let schema = Schema([Purchase.self, Folder.self, Attachment.self])
        if DemoMode.isOn { return MainActor.assumeIsolated { DemoMode.makeContainer(schema: schema) } }
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: local)
            } catch {
                fatalError("Could not open the data store: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            PurchaseListView()
                .environment(store)
                .tint(Theme.brand)
                // Notifications are asked for after the first saved receipt (PurchaseListView),
                // when it's clear what the reminder is for.
        }
        .modelContainer(container)
    }
}
