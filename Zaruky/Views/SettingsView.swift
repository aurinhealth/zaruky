import SwiftUI
import SwiftData
import UIKit

/// App settings: reminders, defaults for new receipts, the unlock, export and contact.
/// Appearance and language follow the phone, so there are no switches for those.
struct SettingsView: View {
    @Environment(PurchaseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Purchase.purchaseDate, order: .reverse) private var purchases: [Purchase]

    @AppStorage(AppSettings.Key.remindersOn) private var remindersOn = true
    @AppStorage(AppSettings.Key.reminderDays) private var reminderDays = AppSettings.defaultReminderDays
    @AppStorage(AppSettings.Key.defaultWarrantyMonths) private var defaultWarranty = AppSettings.defaultWarranty
    @AppStorage(AppSettings.Key.currency) private var currency = AppSettings.defaultCurrency

    @State private var notificationsDenied = false
    @State private var showPaywall = false
    @State private var isRestoring = false
    @State private var restoreNote: String?
    @State private var exporting: ExportService.Kind?
    @State private var exportFile: ExportFile?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Form {
                unlockSection
                remindersSection
                defaultsSection
                dataSection
                aboutSection
            }
            .navigationTitle(L("Nastavení", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(usedCount: purchases.count)
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(url: file.url)
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
            .alert(L("Export se nepovedl", "Export failed"),
                   isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .task { await refreshPermission() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshPermission() } }
            }
            .onChange(of: remindersOn) { _, on in
                Task {
                    if on { await NotificationService.requestAuthorization() }
                    await NotificationService.sync(with: purchases)
                    await refreshPermission()
                }
            }
            .onChange(of: reminderDays) { _, _ in
                Task { await NotificationService.sync(with: purchases) }
            }
        }
    }

    // MARK: Unlock

    private var unlockSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: store.isUnlocked ? "checkmark.seal.fill" : "sparkles")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, store.isUnlocked ? Theme.amber : .white)
                    .frame(width: 48, height: 48)
                    .background((store.isUnlocked ? Theme.brand : Theme.amber).gradient,
                                in: .rect(cornerRadius: Theme.tileRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.isUnlocked ? L("Odemčeno navždy", "Unlocked forever") : L("Verze zdarma", "Free version"))
                        .font(.headline)
                    Text(unlockSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)

            if !store.isUnlocked {
                Button { showPaywall = true } label: {
                    Label {
                        Text(L("Odemknout neomezeně účtenek", "Unlock unlimited receipts"))
                            .fontWeight(.semibold)
                    } icon: {
                        SettingsIcon(symbol: "infinity", color: Theme.brand)
                    }
                }
            }

            Button {
                Task { await restore() }
            } label: {
                HStack {
                    Label {
                        Text(L("Obnovit nákup", "Restore purchase")).foregroundStyle(.primary)
                    } icon: {
                        SettingsIcon(symbol: "arrow.clockwise", color: .blue)
                    }
                    Spacer()
                    if isRestoring { ProgressView() }
                }
            }
            .tint(.primary)
            .disabled(isRestoring)
        } footer: {
            if let restoreNote {
                Text(restoreNote)
            } else if !store.isUnlocked {
                Text(L("Jednorázová platba, žádné předplatné. Platí na všech tvých zařízeních i v Rodinném sdílení.",
                       "One-time payment, no subscription. Works on all your devices and with Family Sharing."))
            }
        }
    }

    private var unlockSubtitle: String {
        if store.isUnlocked {
            return L("Neomezeně účtenek. Díky za podporu!", "Unlimited receipts. Thanks for your support!")
        }
        let used = min(purchases.count, PurchaseStore.freeLimit)
        return L("Využito \(used) z \(PurchaseStore.freeLimit) účtenek zdarma",
                 "\(used) of \(PurchaseStore.freeLimit) free receipts used")
    }

    private func restore() async {
        isRestoring = true
        restoreNote = nil
        store.errorMessage = nil
        await store.restore()
        isRestoring = false
        if store.isUnlocked {
            restoreNote = L("Nákup je obnovený, máš odemčeno.", "Purchase restored, you're unlocked.")
        } else if let error = store.errorMessage {
            restoreNote = error
        } else {
            restoreNote = L("Na tomhle Apple ID jsme žádný nákup nenašli.", "No purchase found for this Apple ID.")
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        Section {
            Toggle(isOn: $remindersOn) {
                Label {
                    Text(L("Připomínat konec záruky", "Remind me before warranties end"))
                } icon: {
                    SettingsIcon(symbol: "bell.badge.fill", color: .red)
                }
            }

            if remindersOn {
                Picker(selection: $reminderDays) {
                    ForEach(dayOptions, id: \.self) { days in
                        Text(L("\(AppFormat.days(days)) předem", "\(AppFormat.days(days)) before")).tag(days)
                    }
                } label: {
                    Label {
                        Text(L("Kdy", "When"))
                    } icon: {
                        SettingsIcon(symbol: "calendar.badge.clock", color: .orange)
                    }
                }

                if notificationsDenied {
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("Upozornění jsou v iOS vypnutá", "Notifications are off in iOS"))
                                    .foregroundStyle(.primary)
                                Text(L("Klepni a povol je v Nastavení iPhonu.", "Tap to allow them in iPhone Settings."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            SettingsIcon(symbol: "exclamationmark.triangle.fill", color: Theme.amber)
                        }
                    }
                    .tint(.primary)
                }
            }
        } header: {
            Text(L("Upozornění", "Reminders"))
        } footer: {
            Text(remindersOn
                 ? L("Připomínka přijde v 9:00, \(AppFormat.days(reminderDays)) před koncem záruky.",
                     "The reminder arrives at 9:00, \(AppFormat.days(reminderDays)) before the warranty ends.")
                 : L("Žádné připomínky nepřijdou. Konec záruky uvidíš jen v appce.",
                     "You won't get any reminders. You'll only see warranty end dates in the app."))
        }
    }

    private var dayOptions: [Int] {
        let options = AppSettings.reminderDayOptions
        return options.contains(reminderDays) ? options : (options + [reminderDays]).sorted()
    }

    private func refreshPermission() async {
        if DemoMode.isOn { return }
        notificationsDenied = await NotificationService.isDenied()
    }

    // MARK: Defaults for new receipts

    private var defaultsSection: some View {
        Section {
            Picker(selection: $defaultWarranty) {
                ForEach(AppSettings.warrantyOptions, id: \.self) { months in
                    Text(AppFormat.warrantyLength(months: months)).tag(months)
                }
            } label: {
                Label {
                    Text(L("Délka záruky", "Warranty length"))
                } icon: {
                    SettingsIcon(symbol: "shield.lefthalf.filled", color: Theme.brand)
                }
            }

            NavigationLink {
                CurrencyPicker(selection: $currency)
            } label: {
                LabeledContent {
                    Text(AppSettings.name(for: currency))
                } label: {
                    Label {
                        Text(L("Měna", "Currency"))
                    } icon: {
                        SettingsIcon(symbol: "banknote.fill", color: .indigo)
                    }
                }
            }
        } header: {
            Text(L("Nové účtenky", "New receipts"))
        } footer: {
            Text(L("Použije se u nově přidaných účtenek, u každé to jde změnit. V EU platí na nové zboží zákonná záruka 24 měsíců.",
                   "Used for new receipts, and you can change it on each one. In the EU, new goods have a 24-month legal warranty."))
        }
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            exportButton(.pdf, title: L("Přehled do PDF", "Overview as PDF"),
                         detail: L("Seznam účtenek a jejich fotky, k tisku", "List of receipts with photos, ready to print"),
                         symbol: "doc.richtext.fill", color: .red)
            exportButton(.zip, title: L("Kompletní záloha (ZIP)", "Full backup (ZIP)"),
                         detail: L("Fotky účtenek, tabulka pro Excel a PDF", "Receipt photos, a spreadsheet and the PDF"),
                         symbol: "archivebox.fill", color: .blue)
        } header: {
            Text(L("Data", "Data"))
        } footer: {
            Text(dataFooter)
        }
    }

    private var dataFooter: String {
        let iCloud = FileManager.default.ubiquityIdentityToken != nil || DemoMode.isOn
        let sync = iCloud
            ? L("Účtenky jsou v tvém iCloudu a synchronizují se mezi tvými zařízeními.",
                "Receipts are in your iCloud and synced across your devices.")
            : L("iCloud není zapnutý, účtenky jsou jen v tomto telefonu.",
                "iCloud is off, so receipts are only on this phone.")
        return sync + " " + L("Data zůstávají u tebe, export si můžeš uložit do Souborů nebo poslat kam chceš.",
                              "Your data stays with you. Save the export to Files or send it wherever you like.")
    }

    private func exportButton(_ kind: ExportService.Kind, title: String, detail: String, symbol: String, color: Color) -> some View {
        Button {
            Task { await export(kind) }
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundStyle(.primary)
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    SettingsIcon(symbol: symbol, color: color)
                }
                Spacer()
                if exporting == kind {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)
        .disabled(purchases.isEmpty || exporting != nil)
    }

    private func export(_ kind: ExportService.Kind) async {
        exporting = kind
        defer { exporting = nil }
        let items = purchases.map(ExportItem.init)
        do {
            exportFile = ExportFile(url: try await ExportService.export(items, as: kind))
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            Button { openURL(AppInfo.reviewURL) } label: {
                Label {
                    Text(L("Ohodnotit v App Storu", "Rate on the App Store")).foregroundStyle(.primary)
                } icon: {
                    SettingsIcon(symbol: "star.fill", color: Theme.amber)
                }
            }
            .tint(.primary)

            ShareLink(item: AppInfo.appStoreURL,
                      message: Text(L("Hlídá mi záruky a účtenky, zkus to taky.", "It keeps track of my warranties and receipts, give it a try."))) {
                Label {
                    Text(L("Doporučit známým", "Tell a friend")).foregroundStyle(.primary)
                } icon: {
                    SettingsIcon(symbol: "heart.fill", color: .pink)
                }
            }
            .tint(.primary)

            if let mail = supportMailURL {
                Button { openURL(mail) } label: {
                    Label {
                        Text(L("Napsat nám", "Contact us")).foregroundStyle(.primary)
                    } icon: {
                        SettingsIcon(symbol: "envelope.fill", color: .teal)
                    }
                }
                .tint(.primary)
            }
        } header: {
            Text(L("O appce", "About"))
        } footer: {
            Text("Záruky \(AppInfo.version)")
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
    }

    private var supportMailURL: URL? {
        guard !AppInfo.supportEmail.isEmpty else { return nil }
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = AppInfo.supportEmail
        parts.queryItems = [
            URLQueryItem(name: "subject", value: L("Záruky – zpětná vazba", "Záruky – feedback")),
            URLQueryItem(name: "body", value: "\n\n—\nZáruky \(AppInfo.version), iOS \(UIDevice.current.systemVersion)"),
        ]
        return parts.url
    }
}

/// Searchable list of every currency, common ones on top.
struct CurrencyPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private func matches(_ code: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return code.localizedCaseInsensitiveContains(q) || AppSettings.name(for: code).localizedCaseInsensitiveContains(q)
    }

    var body: some View {
        List {
            let common = AppSettings.commonCurrencies.filter(matches)
            let other = AppSettings.allCurrencies.filter { !AppSettings.commonCurrencies.contains($0) && matches($0) }
            if !common.isEmpty {
                Section(L("Nejčastější", "Common")) { ForEach(common, id: \.self, content: row) }
            }
            if !other.isEmpty {
                Section(L("Všechny měny", "All currencies")) { ForEach(other, id: \.self, content: row) }
            }
        }
        .navigationTitle(L("Měna", "Currency"))
        .searchable(text: $query, prompt: L("Hledat měnu", "Search currency"))
    }

    private func row(_ code: String) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppSettings.name(for: code)).foregroundStyle(.primary)
                    Text(code).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if code == selection {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Theme.brand)
                }
            }
        }
        .tint(.primary)
    }
}

/// Coloured rounded square with a white symbol, like the rows in iOS Settings.
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: .rect(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// System share sheet, so the export can go to Files, Mail, AirDrop…
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
