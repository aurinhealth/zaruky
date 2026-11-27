import Foundation
import UserNotifications

enum NotificationService {
    static let daysBefore = 30

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func schedule(for purchase: Purchase) {
        let id = purchase.id.uuidString
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let cal = Calendar.current
        guard let reminderDay = cal.date(byAdding: .day, value: -daysBefore, to: purchase.warrantyEndDate) else { return }
        var comps = cal.dateComponents([.year, .month, .day], from: reminderDay)
        comps.hour = 9
        comps.minute = 0
        guard let fireDate = cal.date(from: comps), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        let name = purchase.productName.isEmpty ? L("Nákup", "Purchase") : purchase.productName
        let days = AppFormat.days(daysBefore)
        let end = AppFormat.date(purchase.warrantyEndDate)
        content.title = L("Záruka brzy končí", "Warranty ending soon")
        content.body = L("\(name): záruka skončí za \(days), \(end).",
                         "\(name): the warranty ends in \(days), on \(end).")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
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
        let ids = Set(purchases.map { $0.id.uuidString })
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let stale = pending.filter { !ids.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        for purchase in purchases { schedule(for: purchase) }
    }
}
