import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

/// What the add/edit form is opened with.
struct FormContext: Identifiable {
    let id = UUID()
    var image: UIImage?
}

struct PurchaseListView: View {
    @Environment(PurchaseStore.self) private var store
    @Query(sort: \Purchase.purchaseDate, order: .reverse) private var purchases: [Purchase]

    @State private var searchText = ""
    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var formContext: FormContext?
    @State private var showPaywall = false

    private var filtered: [Purchase] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return purchases }
        return purchases.filter {
            $0.productName.localizedCaseInsensitiveContains(query)
                || $0.storeName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if purchases.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Záruky")
            .searchable(text: $searchText, prompt: "Hledat produkt nebo obchod")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { addMenu }
            }
            .navigationDestination(for: Purchase.self) { PurchaseDetailView(purchase: $0) }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { image in
                showScanner = false
                if let image { formContext = FormContext(image: image) }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    formContext = FormContext(image: image)
                }
                photoItem = nil
            }
        }
        .sheet(item: $formContext) { context in
            PurchaseFormView(purchase: nil, image: context.image)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private var list: some View {
        List {
            ForEach(WarrantyStatus.allCases) { status in
                let items = filtered.filter { $0.status == status }
                if !items.isEmpty {
                    Section(status.title) {
                        ForEach(items) { purchase in
                            NavigationLink(value: purchase) {
                                PurchaseRow(purchase: purchase)
                            }
                        }
                    }
                }
            }
            if !store.isUnlocked {
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        Label(freeLabel, systemImage: "lock.open")
                    }
                }
            }
        }
        .overlay {
            if filtered.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private var freeLabel: String {
        let left = max(PurchaseStore.freeLimit - purchases.count, 0)
        return "Zdarma zbývá: \(left) z \(PurchaseStore.freeLimit). Odemknout navždy"
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Zatím žádné účtenky", systemImage: "doc.text.viewfinder")
        } description: {
            Text("Naskenuj účtenku a appka ti připomene, než skončí záruka.")
        } actions: {
            Button("Naskenovat účtenku") { start(.scan) }
                .buttonStyle(.borderedProminent)
        }
    }

    private var addMenu: some View {
        Menu {
            Button { start(.scan) } label: { Label("Naskenovat", systemImage: "doc.viewfinder") }
            Button { start(.photo) } label: { Label("Vybrat z Fotek", systemImage: "photo") }
            Button { start(.manual) } label: { Label("Zadat ručně", systemImage: "square.and.pencil") }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Přidat účtenku")
    }

    private enum AddSource { case scan, photo, manual }

    private func start(_ source: AddSource) {
        guard store.canAdd(currentCount: purchases.count) else {
            showPaywall = true
            return
        }
        switch source {
        case .scan:
            if VNDocumentCameraViewController.isSupported {
                showScanner = true
            } else {
                showPhotoPicker = true
            }
        case .photo:
            showPhotoPicker = true
        case .manual:
            formContext = FormContext(image: nil)
        }
    }
}

struct PurchaseRow: View {
    let purchase: Purchase

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(purchase.productName.isEmpty ? "Bez názvu" : purchase.productName)
                    .font(.headline)
                    .lineLimit(1)
                Text(purchase.storeName.isEmpty ? CzechFormat.date(purchase.purchaseDate) : purchase.storeName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(CzechFormat.remaining(days: purchase.daysRemaining))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badgeColor.opacity(0.15), in: Capsule())
                .foregroundStyle(badgeColor)
        }
    }

    private var badgeColor: Color {
        switch purchase.status {
        case .expiringSoon: .orange
        case .active: .green
        case .expired: .secondary
        }
    }
}
