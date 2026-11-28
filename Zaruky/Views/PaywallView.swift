import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(PurchaseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showPrivacy = false
    /// How many receipts the user already has, to say why they're seeing this.
    var usedCount: Int = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    hero
                    VStack(spacing: 8) {
                        Text(store.isUnlocked ? L("Odemčeno, díky!", "Unlocked, thank you!", "Freigeschaltet, danke!")
                                              : L("Hlídej všechny záruky", "Keep every warranty safe", "Jede Garantie sicher aufbewahrt"))
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 0) {
                        benefit("infinity", .green, L("Neomezeně účtenek", "Unlimited receipts", "Unbegrenzt viele Belege"),
                                L("Elektronika, spotřebiče, nábytek, kolo…", "Electronics, appliances, furniture, bikes…", "Elektronik, Haushaltsgeräte, Möbel, Fahrräder…"))
                        Divider().padding(.leading, 66)
                        benefit("bell.badge.fill", .orange, L("Připomínky před koncem záruky", "Reminders before warranties end", "Erinnerungen vor Garantieende"),
                                L("U každé účtenky, \(AppFormat.days(AppSettings.reminderDays)) předem.", "For every receipt, \(AppFormat.days(AppSettings.reminderDays)) ahead.", "Für jeden Beleg, \(AppFormat.days(AppSettings.reminderDays)) vorher."))
                        Divider().padding(.leading, 66)
                        benefit("lock.icloud.fill", .blue, L("Jen ve tvém iCloudu", "Only in your iCloud", "Nur in deiner iCloud"),
                                L("Žádný účet, žádné servery třetích stran.", "No account, no third-party servers.", "Kein Konto, keine fremden Server."))
                        Divider().padding(.leading, 66)
                        benefit("person.2.fill", .purple, L("Pro celou rodinu", "For the whole family", "Für die ganze Familie"),
                                L("Funguje v Rodinném sdílení.", "Works with Family Sharing.", "Funktioniert mit der Familienfreigabe."))
                    }
                    .card()
                }
                .padding(.horizontal, 20)
                // Room for the purchase bar, so the last benefit is never under it.
                .padding(.bottom, 200)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaBar(edge: .bottom) { purchaseBar }
            .scrollEdgeEffectStyle(.hard, for: .bottom)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .task {
                if store.product == nil { await store.loadProduct() }
            }
            .sheet(isPresented: $showPrivacy) { PrivacyView() }
        }
    }

    /// "129 Kč" rather than StoreKit's "129,00 Kč" for whole amounts.
    private static func price(of product: Product) -> String {
        let value = NSDecimalNumber(decimal: product.price).doubleValue
        return AppFormat.price(value, currency: product.priceFormatStyle.currencyCode)
    }

    private var subtitle: String {
        if store.isUnlocked {
            return L("Teď můžeš ukládat neomezeně účtenek.", "You can now save as many receipts as you like.", "Du kannst jetzt beliebig viele Belege speichern.")
        }
        if usedCount >= PurchaseStore.freeLimit {
            return L("Využil jsi \(PurchaseStore.freeLimit) účtenek zdarma. Jednou zaplatíš a máš klid napořád.", "You've used your \(PurchaseStore.freeLimit) free receipts. Pay once and you're set for good.", "Deine \(PurchaseStore.freeLimit) Gratis-Belege sind aufgebraucht. Einmal zahlen, und es ist für immer erledigt.")
        }
        return L("Jednou zaplatíš a máš klid napořád. Žádné předplatné.", "Pay once and you're set for good. No subscription.", "Einmal zahlen, und es ist für immer erledigt. Kein Abo.")
    }

    private var hero: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.amber.opacity(0.35), .clear], center: .center, startRadius: 10, endRadius: 110))
                .frame(width: 220, height: 220)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.70, blue: 0.50), Color(red: 0.03, green: 0.42, blue: 0.31)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 112, height: 112)
                .overlay {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(red: 0.03, green: 0.36, blue: 0.26), Theme.amber)
                }
                .shadow(color: Color(red: 0.03, green: 0.42, blue: 0.31).opacity(0.35), radius: 18, y: 8)
        }
        .frame(height: 180)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    private func benefit(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(color.gradient, in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    private var purchaseBar: some View {
        VStack(spacing: 10) {
            if store.isUnlocked {
                Button { dismiss() } label: {
                    Text(L("Hotovo", "Done", "Fertig"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            } else {
                if store.loadFailed && !DemoMode.isOn {
                    Text(L("Nabídku se teď nepodařilo načíst z App Storu. Zkontroluj připojení k internetu a zkus to znovu.", "Couldn't load the offer from the App Store. Check your internet connection and try again.", "Das Angebot aus dem App Store ließ sich nicht laden. Prüf deine Internetverbindung und versuch es noch einmal."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task {
                        if store.product == nil && !DemoMode.isOn {
                            await store.loadProduct()
                            return
                        }
                        await store.buy()
                        if store.isUnlocked { dismiss() }
                    }
                } label: {
                    Group {
                        if store.isPurchasing || store.isLoading {
                            ProgressView()
                        } else if DemoMode.isOn {
                            // Store screenshots show the local price, not the StoreKit test storefront's.
                            Text(L("Odemknout navždy za ", "Unlock forever for ", "Für immer freischalten für ") + DemoMode.unlockPrice)
                        } else if let product = store.product {
                            Text(L("Odemknout navždy za ", "Unlock forever for ", "Für immer freischalten für ") + Self.price(of: product))
                        } else {
                            Label(L("Zkusit znovu", "Try again", "Erneut versuchen"), systemImage: "arrow.clockwise")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(store.isPurchasing || store.isLoading)

                HStack(spacing: 6) {
                    Text(L("Jednorázová platba", "One-time payment", "Einmalzahlung"))
                    Text("·")
                    Button(L("Obnovit nákup", "Restore purchase", "Kauf wiederherstellen")) {
                        Task { await store.restore() }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Button(L("Podmínky", "Terms", "Bedingungen")) { openURL(AppInfo.termsURL) }
                    Text("·")
                    Button(L("Soukromí", "Privacy", "Datenschutz")) { showPrivacy = true }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let error = store.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}
