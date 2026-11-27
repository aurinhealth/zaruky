import Foundation

/// User preferences from the Settings screen. They live in UserDefaults on this device
/// (not in the synced store), so adding a setting never needs a CloudKit schema change.
/// Views read them with `@AppStorage(AppSettings.Key.…)` using the same defaults as below.
enum AppSettings {
    enum Key {
        static let remindersOn = "settings.remindersOn"
        static let reminderDays = "settings.reminderDays"
        static let defaultWarrantyMonths = "settings.defaultWarrantyMonths"
        static let currency = "settings.currency"
    }

    static let defaultReminderDays = 30
    static let defaultWarranty = 24
    static let defaultCurrency = "CZK"

    static let reminderDayOptions = [7, 14, 30, 60, 90]
    static let warrantyOptions = [6, 12, 24, 36, 48, 60]
    /// Currencies people around here actually pay in, shown first and in the receipt form.
    static let commonCurrencies = ["CZK", "EUR", "USD", "GBP", "PLN", "HUF", "CHF"]

    /// Every currency iOS knows, common ones first, the rest sorted by name in the app language.
    static let allCurrencies: [String] = {
        let rest = Locale.commonISOCurrencyCodes
            .filter { !commonCurrencies.contains($0) }
            .sorted { name(for: $0).localizedStandardCompare(name(for: $1)) == .orderedAscending }
        return commonCurrencies + rest
    }()

    private static var store: UserDefaults { .standard }

    static var remindersOn: Bool {
        store.object(forKey: Key.remindersOn) as? Bool ?? true
    }

    static var reminderDays: Int {
        let value = store.integer(forKey: Key.reminderDays)
        return value > 0 ? value : defaultReminderDays
    }

    static var defaultWarrantyMonths: Int {
        let value = store.integer(forKey: Key.defaultWarrantyMonths)
        return value > 0 ? value : defaultWarranty
    }

    static var currency: String {
        store.string(forKey: Key.currency) ?? defaultCurrency
    }

    /// Short symbol shown next to the price field, e.g. "Kč", "€".
    static func symbol(for code: String) -> String {
        switch code {
        case "CZK": L("Kč", "CZK")
        case "EUR": "€"
        case "USD": "$"
        case "GBP": "£"
        case "PLN": "zł"
        case "HUF": "Ft"
        case "CHF": "CHF"
        default: code
        }
    }

    /// "Česká koruna", "Euro"… in the app language.
    static func name(for code: String) -> String {
        let name = L10n.locale.localizedString(forCurrencyCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// App Store and support details used by Settings.
enum AppInfo {
    /// Apple ID of "Záruky – účtenky" in App Store Connect.
    static let appStoreID = "6839827530"
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
    static let reviewURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!

    /// Apple's standard licence agreement, which covers the one-time purchase.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Address for "Napsat nám" (contact). Left empty, the row is hidden.
    static let supportEmail = "petr.bouma@aurin.health"

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
