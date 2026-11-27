import SwiftUI
import SwiftData

struct PurchaseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let purchase: Purchase

    @State private var showEdit = false
    @State private var showImage = false
    @State private var confirmDelete = false

    private var receiptImage: UIImage? {
        purchase.receiptImageData.flatMap { UIImage(data: $0) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(statusText)
                        .font(.title3.weight(.semibold))
                    ProgressView(value: purchase.elapsedFraction)
                        .tint(purchase.status == .expiringSoon ? Color.orange : Color.accentColor)
                    HStack {
                        Text(AppFormat.date(purchase.purchaseDate))
                        Spacer()
                        Text(AppFormat.date(purchase.warrantyEndDate))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section(L("Nákup", "Purchase")) {
                LabeledContent(L("Obchod", "Store"), value: purchase.storeName.isEmpty ? "—" : purchase.storeName)
                LabeledContent(L("Datum", "Date"), value: AppFormat.date(purchase.purchaseDate))
                LabeledContent(L("Cena", "Price"), value: AppFormat.price(purchase.price, currency: purchase.currencyCode))
                LabeledContent(L("Záruka", "Warranty"), value: AppFormat.warrantyLength(months: purchase.warrantyMonths))
                LabeledContent(L("Složka", "Folder"), value: purchase.folder?.name ?? L("Bez složky", "No folder"))
            }

            if !purchase.notes.isEmpty {
                Section(L("Poznámka", "Note")) { Text(purchase.notes) }
            }

            if let receiptImage {
                Section(L("Účtenka", "Receipt")) {
                    Button { showImage = true } label: {
                        Image(uiImage: receiptImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)

                    ShareLink(
                        item: Image(uiImage: receiptImage),
                        preview: SharePreview(L("Účtenka – ", "Receipt – ") + purchase.productName, image: Image(uiImage: receiptImage))
                    ) {
                        Label(L("Sdílet účtenku k reklamaci", "Share receipt for a claim"), systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                Button(L("Smazat", "Delete"), role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(purchase.productName.isEmpty ? L("Detail", "Details") : purchase.productName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(L("Upravit", "Edit")) { showEdit = true }
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
        }
    }

    private var statusText: String {
        let days = purchase.daysRemaining
        if days < 0 { return L("Záruka skončila", "Warranty has ended") }
        if days == 0 { return L("Záruka končí dnes", "Warranty ends today") }
        return L("Záruka ještě ", "Warranty left: ") + AppFormat.remaining(days: days)
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
