import SwiftUI

/// Plain-language privacy policy: what the app stores and where.
struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    /// Shown as a sheet (from the paywall) or pushed (from Settings).
    var inSheet = true

    var body: some View {
        if inSheet {
            NavigationStack { content.toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Hotovo", "Done", "Fertig")) { dismiss() } }
            } }
        } else {
            content
        }
    }

    private var content: some View {
        List {
            point("lock.icloud.fill", .blue,
                  L("Data jsou jen u tebe", "Your data stays with you", "Deine Daten bleiben bei dir"),
                  L("Účtenky, fotky a poznámky se ukládají v tomto zařízení a v tvém soukromém iCloudu. Nemáme k nim přístup a nemáme žádné vlastní servery.", "Receipts, photos and notes are stored on this device and in your private iCloud. We can't access them and run no servers of our own.", "Belege, Fotos und Notizen werden auf diesem Gerät und in deiner privaten iCloud gespeichert. Wir haben keinen Zugriff darauf und betreiben keine eigenen Server."))
            point("text.viewfinder", .green,
                  L("Čtení účtenek v telefonu", "Receipts are read on the phone", "Belege werden auf dem iPhone gelesen"),
                  L("Text z účtenky čte telefon sám (Apple Vision a Apple Intelligence). Nic se nikam neposílá.", "The phone reads the receipt itself (Apple Vision and Apple Intelligence). Nothing is sent anywhere.", "Das iPhone liest den Beleg selbst (Apple Vision und Apple Intelligence). Nichts wird irgendwohin gesendet."))
            point("chart.bar.xaxis", .orange,
                  L("Žádné sledování", "No tracking", "Kein Tracking"),
                  L("Appka nepoužívá analytiku, reklamy ani sledování. Nesbíráme žádné osobní údaje.", "The app has no analytics, ads or tracking. We collect no personal data.", "Die App hat keine Analyse, keine Werbung und kein Tracking. Wir sammeln keine persönlichen Daten."))
            point("creditcard.fill", .purple,
                  L("Platba přes Apple", "Payment through Apple", "Bezahlung über Apple"),
                  L("Odemčení platíš přes App Store. Údaje o platbě vidí jen Apple.", "You pay for the unlock through the App Store. Only Apple sees your payment details.", "Die Freischaltung bezahlst du über den App Store. Deine Zahlungsdaten sieht nur Apple."))
            point("trash.fill", .red,
                  L("Smazání", "Deleting", "Löschen"),
                  L("Když účtenku smažeš, zmizí ze všech tvých zařízení. Smazáním appky a dat v iCloudu (Nastavení › iCloud) zmizí všechno.", "Deleting a receipt removes it from all your devices. Deleting the app and its iCloud data (Settings › iCloud) removes everything.", "Ein gelöschter Beleg verschwindet von allen deinen Geräten. Wenn du die App und ihre iCloud-Daten löschst (Einstellungen › iCloud), ist alles weg."))
            if !AppInfo.supportEmail.isEmpty {
                Section {
                    Text(L("Dotazy: \(AppInfo.supportEmail)", "Questions: \(AppInfo.supportEmail)", "Fragen: \(AppInfo.supportEmail)"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(L("Ochrana soukromí", "Privacy", "Datenschutz"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func point(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(text).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}
