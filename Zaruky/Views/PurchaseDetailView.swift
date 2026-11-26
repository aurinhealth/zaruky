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
                        Text(CzechFormat.date(purchase.purchaseDate))
                        Spacer()
                        Text(CzechFormat.date(purchase.warrantyEndDate))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Nákup") {
                LabeledContent("Obchod", value: purchase.storeName.isEmpty ? "—" : purchase.storeName)
                LabeledContent("Datum", value: CzechFormat.date(purchase.purchaseDate))
                LabeledContent("Cena", value: CzechFormat.price(purchase.price, currency: purchase.currencyCode))
                LabeledContent("Záruka", value: CzechFormat.warrantyLength(months: purchase.warrantyMonths))
            }

            if !purchase.notes.isEmpty {
                Section("Poznámka") { Text(purchase.notes) }
            }

            if let receiptImage {
                Section("Účtenka") {
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
                        preview: SharePreview("Účtenka – \(purchase.productName)", image: Image(uiImage: receiptImage))
                    ) {
                        Label("Sdílet účtenku k reklamaci", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                Button("Smazat", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(purchase.productName.isEmpty ? "Detail" : purchase.productName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Upravit") { showEdit = true }
        }
        .sheet(isPresented: $showEdit) {
            PurchaseFormView(purchase: purchase, image: nil)
        }
        .fullScreenCover(isPresented: $showImage) {
            if let receiptImage {
                ReceiptImageViewer(image: receiptImage)
            }
        }
        .confirmationDialog("Smazat účtenku?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Smazat", role: .destructive) { delete() }
        }
    }

    private var statusText: String {
        let days = purchase.daysRemaining
        if days < 0 { return "Záruka skončila" }
        if days == 0 { return "Záruka končí dnes" }
        return "Záruka ještě " + CzechFormat.remaining(days: days)
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
                    Button("Hotovo") { dismiss() }
                }
            }
        }
    }
}
