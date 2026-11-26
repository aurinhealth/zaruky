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
        let name = purchase.productName.isEmpty ? "Nákup" : purchase.productName
        content.title = "Záruka brzy končí"
        content.body = "\(name): záruka skončí za \(CzechFormat.days(daysBefore)), \(CzechFormat.date(purchase.warrantyEndDate))."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel(for purchase: Purchase) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [purchase.id.uuidString])
    }
}
