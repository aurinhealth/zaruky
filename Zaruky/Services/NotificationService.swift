import Foundation
import UserNotifications

enum NotificationService {
    /// How many days before the warranty ends the reminder fires (Settings).
    static var daysBefore: Int { AppSettings.reminderDays }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// True while iOS has never asked the user about notifications for this app.
    static func notAskedYet() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
    }

    static func schedule(for purchase: Purchase) {
        let id = purchase.id.uuidString
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard AppSettings.remindersOn else { return }

        let cal = Calendar.current
        guard let reminderDay = cal.date(byAdding: .day, value: -daysBefore, to: purchase.warrantyEndDate) else { return }
        var comps = cal.dateComponents([.year, .month, .day], from: reminderDay)
        comps.hour = 9
        comps.minute = 0
        guard let fireDate = cal.date(from: comps), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        let name = purchase.productName.isEmpty ? L("Nákup", "Purchase", "Kauf") : purchase.productName
        let days = AppFormat.days(daysBefore)
        let end = AppFormat.date(purchase.warrantyEndDate)
        content.title = L("Záruka brzy končí", "Warranty ending soon", "Garantie endet bald")
        content.body = L("\(name): záruka skončí za \(days), \(end).", "\(name): the warranty ends in \(days), on \(end).", "\(name): Die Garantie endet in \(days), am \(end).")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Whether iOS lets the app show notifications at all (the user may have turned them off in iOS Settings).
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    static func cancel(for purchase: Purchase) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [purchase.id.uuidString])
    }

    /// Reminders are local to each device, so receipts that arrive through iCloud
    /// (or are deleted on another device) are reconciled here.
    @MainActor
    static func sync(with purchases: [Purchase]) async {
        let center = UNUserNotificationCenter.current()
        guard AppSettings.remindersOn else {
            center.removeAllPendingNotificationRequests()
            return
        }
        let ids = Set(purchases.map { $0.id.uuidString })
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let stale = pending.filter { !ids.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        for purchase in purchases { schedule(for: purchase) }
    }
}
