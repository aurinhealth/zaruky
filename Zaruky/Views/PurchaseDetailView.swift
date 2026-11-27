import SwiftUI
import SwiftData

struct PurchaseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.createdAt) private var folderQuery: [Folder]
    let purchase: Purchase

    @State private var showEdit = false
    @State private var showImage = false
    @State private var confirmDelete = false

    private var receiptImage: UIImage? {
        purchase.receiptImageData.flatMap { UIImage(data: $0) }
    }

    private var folders: [Folder] {
        folderQuery.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                statusCard
                infoCard
                if !purchase.notes.isEmpty { notesCard }
                receiptCard
                claimTip
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(purchase.productName.isEmpty ? L("Detail", "Details") : purchase.productName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L("Upravit", "Edit")) { showEdit = true }
            }
            ToolbarItem(placement: .primaryAction) { moreMenu }
        }
        .sheet(isPresented: $showEdit) {
            PurchaseFormView(purchase: purchase, image: nil)
        }
        .fullScreenCover(isPresented: $showImage) {
            if let receiptImage {
                ReceiptImageViewer(image: receiptImage)
            }
        }
        .confirmationDialog(L("Smazat účtenku?", "Delete receipt?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Smazat", "Delete"), role: .destructive) { delete() }
        } message: {
            Text(L("Účtenka i připomínka zmizí ze všech tvých zařízení.",
                   "The receipt and its reminder are removed from all your devices."))
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 10) {
            ProductTile(name: purchase.productName, status: purchase.status, size: 72)
            Text(purchase.productName.isEmpty ? L("Bez názvu", "Untitled") : purchase.productName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if !purchase.storeName.isEmpty || purchase.folder != nil {
                HStack(spacing: 6) {
                    if !purchase.storeName.isEmpty {
                        Label(purchase.storeName, systemImage: "storefront")
                    }
                    if let folder = purchase.folder {
                        Label(folder.name, systemImage: "folder")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private var statusCard: some View {
        let status = purchase.status
        let days = purchase.daysRemaining
        return HStack(spacing: 18) {
            ZStack {
                WarrantyRing(remaining: 1 - purchase.elapsedFraction, color: status.color, lineWidth: 9)
                VStack(spacing: 0) {
                    Text(ringValue(days))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(ringUnit(days))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                Label(statusTitle, systemImage: status.symbol)
                    .font(.headline)
                    .foregroundStyle(status.color)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .card()
        .accessibilityElement(children: .combine)
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow(L("Koupeno", "Bought"), AppFormat.date(purchase.purchaseDate), symbol: "calendar")
            Divider().padding(.leading, 52)
            infoRow(L("Záruka do", "Warranty until"), AppFormat.date(purchase.warrantyEndDate), symbol: "calendar.badge.checkmark")
            Divider().padding(.leading, 52)
            infoRow(L("Délka záruky", "Warranty length"), AppFormat.warrantyLength(months: purchase.warrantyMonths), symbol: "shield.lefthalf.filled")
            Divider().padding(.leading, 52)
            infoRow(L("Cena", "Price"), AppFormat.price(purchase.price, currency: purchase.currencyCode), symbol: "creditcard")
        }
        .card()
    }

    private func infoRow(_ title: String, _ value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Theme.brand)
                .frame(width: 28)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("Poznámka", "Note"), systemImage: "note.text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(purchase.notes)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(14)
        .card()
    }

    @ViewBuilder
    private var receiptCard: some View {
        if let receiptImage {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Účtenka", "Receipt"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button { showImage = true } label: {
                    Image(uiImage: receiptImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.footnote.weight(.semibold))
                                .padding(9)
                                .glassEffect(.regular, in: .circle)
                                .padding(10)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Zobrazit účtenku", "View receipt"))

                ShareLink(
                    item: Image(uiImage: receiptImage),
                    preview: SharePreview(L("Účtenka – ", "Receipt – ") + purchase.productName, image: Image(uiImage: receiptImage))
                ) {
                    Label(L("Poslat účtenku k reklamaci", "Send receipt for a claim"), systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .padding(14)
            .card()
        } else {
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(L("K tomuhle nákupu nemáš fotku účtenky. Při reklamaci se hodí.",
                       "There's no photo of the receipt for this purchase. It helps with a claim."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card()
        }
    }

    @ViewBuilder
    private var claimTip: some View {
        if purchase.status != .expired {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Theme.amber)
                Text(L("Reklamaci uplatníš u prodejce, kde jsi zboží koupil. Stačí účtenka a popis závady, prodejce má na vyřízení 30 dní.",
                       "Make a claim with the store you bought it from. The receipt and a description of the fault are enough; the store has 30 days to resolve it."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        }
    }

    private var moreMenu: some View {
        Menu {
            Menu {
                Button { move(to: nil) } label: {
                    if purchase.folder == nil { Label(L("Bez složky", "No folder"), systemImage: "checkmark") }
                    else { Text(L("Bez složky", "No folder")) }
                }
                ForEach(folders) { folder in
                    Button { move(to: folder) } label: {
                        if purchase.folder?.id == folder.id { Label(folder.name, systemImage: "checkmark") }
                        else { Text(folder.name) }
                    }
                }
            } label: {
                Label(L("Přesunout do složky", "Move to folder"), systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: {
                Label(L("Smazat", "Delete"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(L("Další akce", "More actions"))
    }

    // MARK: Text

    private var statusTitle: String {
        switch purchase.status {
        case .active: L("Kryto zárukou", "Covered")
        case .expiringSoon: L("Záruka brzy končí", "Warranty ending soon")
        case .expired: L("Záruka skončila", "Warranty has ended")
        }
    }

    private var statusText: String {
        let days = purchase.daysRemaining
        let end = AppFormat.date(purchase.warrantyEndDate)
        if days < 0 { return L("Skončila \(end).", "It ended on \(end).") }
        if days == 0 { return L("Končí dnes. Pokud něco nefunguje, reklamuj to ještě dnes.",
                                "It ends today. If something is wrong, make a claim today.") }
        if purchase.status == .expiringSoon {
            return L("Končí \(end). Zkontroluj, jestli všechno funguje, dokud je čas.",
                     "It ends on \(end). Check everything still works while there's time.")
        }
        guard AppSettings.remindersOn else { return L("Do \(end).", "Until \(end).") }
        return L("Do \(end). Připomeneme se \(AppFormat.days(NotificationService.daysBefore)) předem.",
                 "Until \(end). We'll remind you \(AppFormat.days(NotificationService.daysBefore)) before.")
    }

    private func ringValue(_ days: Int) -> String {
        if days < 0 { return "0" }
        if days <= 60 { return "\(days)" }
        let months = days / 30
        return months < 24 ? "\(months)" : "\(months / 12)"
    }

    private func ringUnit(_ days: Int) -> String {
        if days < 0 { return L("dní", "days") }
        if days <= 60 {
            return L10n.isEnglish ? (days == 1 ? "day" : "days")
                : AppFormat.czechPlural(days, one: "den", few: "dny", many: "dní")
        }
        let months = days / 30
        if months < 24 {
            return L10n.isEnglish ? "months" : AppFormat.czechPlural(months, one: "měsíc", few: "měsíce", many: "měsíců")
        }
        let years = months / 12
        return L10n.isEnglish ? (years == 1 ? "year" : "years") : AppFormat.czechPlural(years, one: "rok", few: "roky", many: "let")
    }

    // MARK: Actions

    private func move(to folder: Folder?) {
        purchase.folder = folder
        try? modelContext.save()
    }

    private func delete() {
        let target = purchase
        NotificationService.cancel(for: target)
        dismiss()
        // Delete after the detail is gone so the view never renders a deleted model.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            modelContext.delete(target)
            try? modelContext.save()
        }
    }
}

struct ReceiptImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) })
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Hotovo", "Done")) { dismiss() }
                }
            }
        }
    }
}
