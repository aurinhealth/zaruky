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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Purchase.purchaseDate, order: .reverse) private var purchases: [Purchase]
    @Query(sort: \Folder.createdAt) private var folderQuery: [Folder]

    @State private var searchText = ""
    @State private var filter: FolderFilter = .all
    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var formContext: FormContext?
    @State private var showPaywall = false

    // Folder editing
    @State private var showFolderEditor = false
    @State private var editingFolder: Folder?
    @State private var folderName = ""
    @State private var folderToDelete: Folder?

    private var folders: [Folder] {
        folderQuery.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedFolder: Folder? {
        if case .folder(let id) = filter { return folders.first { $0.id == id } }
        return nil
    }

    private var filtered: [Purchase] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return purchases.filter { purchase in
            guard filter.matches(purchase) else { return false }
            guard !query.isEmpty else { return true }
            return purchase.productName.localizedCaseInsensitiveContains(query)
                || purchase.storeName.localizedCaseInsensitiveContains(query)
                || purchase.notes.localizedCaseInsensitiveContains(query)
        }
    }

    private var title: String {
        switch filter {
        case .all: L("Záruky", "Warranties")
        case .unfiled: L("Bez složky", "No folder")
        case .folder: selectedFolder?.name ?? L("Záruky", "Warranties")
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if purchases.isEmpty && folders.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle(title)
            .searchable(text: $searchText, prompt: L("Hledat produkt nebo obchod", "Search product or store"))
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
            PurchaseFormView(purchase: nil, image: context.image, initialFolder: selectedFolder)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert(editingFolder == nil ? L("Nová složka", "New folder") : L("Přejmenovat složku", "Rename folder"),
               isPresented: $showFolderEditor) {
            TextField(L("Název složky", "Folder name"), text: $folderName)
            Button(L("Uložit", "Save")) { saveFolder() }
            Button(L("Zrušit", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("Např. Elektronika, Domácnost, Auto", "E.g. Electronics, Home, Car"))
        }
        .confirmationDialog(
            L("Smazat složku „\(folderToDelete?.name ?? "")“?", "Delete folder “\(folderToDelete?.name ?? "")”?"),
            isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("Smazat složku", "Delete folder"), role: .destructive) { deleteFolder() }
        } message: {
            Text(L("Účtenky ve složce zůstanou, jen budou bez složky.",
                   "Receipts in the folder are kept, they just won't be in a folder."))
        }
        .task(id: purchases.count) { await NotificationService.sync(with: purchases) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await NotificationService.sync(with: purchases) } }
        }
        .onChange(of: folders.map(\.id)) { _, ids in
            // The selected folder may have been deleted, here or on another device.
            if case .folder(let id) = filter, !ids.contains(id) { filter = .all }
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
                                PurchaseRow(purchase: purchase, showFolder: filter == .all)
                            }
                            .contextMenu { moveMenu(for: purchase) }
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
            Section {
            } footer: {
                SyncStatusFooter()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FolderBar(
                folders: folders,
                purchases: purchases,
                selection: $filter,
                onNew: { startNewFolder() },
                onRename: { startRename($0) },
                onDelete: { folderToDelete = $0 }
            )
            .background(.bar)
        }
        .overlay {
            if filtered.isEmpty {
                if !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if !purchases.isEmpty || filter != .all {
                    ContentUnavailableView {
                        Label(L("Složka je prázdná", "This folder is empty"), systemImage: "folder")
                    } description: {
                        Text(L("Přidej sem účtenku přes + nebo ji přesuň podržením prstu v seznamu.",
                               "Add a receipt with + or move one here by long-pressing it in the list."))
                    }
                } else {
                    ContentUnavailableView {
                        Label(L("Zatím žádné účtenky", "No receipts yet"), systemImage: "doc.text.viewfinder")
                    } actions: {
                        Button(L("Naskenovat účtenku", "Scan a receipt")) { start(.scan) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func moveMenu(for purchase: Purchase) -> some View {
        Menu {
            Button {
                move(purchase, to: nil)
            } label: {
                if purchase.folder == nil {
                    Label(L("Bez složky", "No folder"), systemImage: "checkmark")
                } else {
                    Text(L("Bez složky", "No folder"))
                }
            }
            ForEach(folders) { folder in
                Button {
                    move(purchase, to: folder)
                } label: {
                    if purchase.folder?.id == folder.id {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
            }
            Divider()
            Button {
                startNewFolder()
            } label: {
                Label(L("Nová složka", "New folder"), systemImage: "folder.badge.plus")
            }
        } label: {
            Label(L("Přesunout do složky", "Move to folder"), systemImage: "folder")
        }
    }

    private var freeLabel: String {
        let left = max(PurchaseStore.freeLimit - purchases.count, 0)
        let total = PurchaseStore.freeLimit
        return L("Zdarma zbývá: \(left) z \(total). Odemknout navždy",
                 "Free receipts left: \(left) of \(total). Unlock forever")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L("Zatím žádné účtenky", "No receipts yet"), systemImage: "doc.text.viewfinder")
        } description: {
            Text(L("Naskenuj účtenku a appka ti připomene, než skončí záruka.",
                   "Scan a receipt and the app reminds you before the warranty ends."))
        } actions: {
            Button(L("Naskenovat účtenku", "Scan a receipt")) { start(.scan) }
                .buttonStyle(.borderedProminent)
            Button(L("Vytvořit složku", "Create a folder")) { startNewFolder() }
        }
    }

    private var addMenu: some View {
        Menu {
            Button { start(.scan) } label: { Label(L("Naskenovat", "Scan"), systemImage: "doc.viewfinder") }
            Button { start(.photo) } label: { Label(L("Vybrat z Fotek", "Choose from Photos"), systemImage: "photo") }
            Button { start(.manual) } label: { Label(L("Zadat ručně", "Enter manually"), systemImage: "square.and.pencil") }
            Divider()
            Button { startNewFolder() } label: { Label(L("Nová složka", "New folder"), systemImage: "folder.badge.plus") }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(L("Přidat", "Add"))
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

    // MARK: Folders

    private func startNewFolder() {
        editingFolder = nil
        folderName = ""
        showFolderEditor = true
    }

    private func startRename(_ folder: Folder) {
        editingFolder = folder
        folderName = folder.name
        showFolderEditor = true
    }

    private func saveFolder() {
        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let editingFolder {
            editingFolder.name = name
        } else {
            let folder = Folder(name: name)
            modelContext.insert(folder)
            filter = .folder(folder.id)
        }
        try? modelContext.save()
        editingFolder = nil
    }

    private func deleteFolder() {
        guard let folder = folderToDelete else { return }
        if case .folder(let id) = filter, id == folder.id { filter = .all }
        for purchase in folder.purchases ?? [] { purchase.folder = nil }
        modelContext.delete(folder)
        try? modelContext.save()
        folderToDelete = nil
    }

    private func move(_ purchase: Purchase, to folder: Folder?) {
        purchase.folder = folder
        try? modelContext.save()
    }
}

/// Horizontal folder chips above the list: all, each folder, unfiled, and a button for a new folder.
struct FolderBar: View {
    let folders: [Folder]
    let purchases: [Purchase]
    @Binding var selection: FolderFilter
    var onNew: () -> Void
    var onRename: (Folder) -> Void
    var onDelete: (Folder) -> Void

    private var unfiledCount: Int { purchases.filter { $0.folder == nil }.count }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(L("Vše", "All"), count: purchases.count, icon: "tray.full", filter: .all)
                ForEach(folders) { folder in
                    chip(folder.name, count: folder.purchaseCount, icon: "folder", filter: .folder(folder.id))
                        .contextMenu {
                            Button { onRename(folder) } label: {
                                Label(L("Přejmenovat", "Rename"), systemImage: "pencil")
                            }
                            Button(role: .destructive) { onDelete(folder) } label: {
                                Label(L("Smazat složku", "Delete folder"), systemImage: "trash")
                            }
                        }
                }
                if !folders.isEmpty && unfiledCount > 0 {
                    chip(L("Bez složky", "No folder"), count: unfiledCount, icon: "tray", filter: .unfiled)
                }
                Button(action: onNew) {
                    Label(L("Složka", "Folder"), systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L("Nová složka", "New folder"))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, count: Int, icon: String, filter: FolderFilter) -> some View {
        let isSelected = selection == filter
        return Button {
            selection = filter
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).lineLimit(1)
                Text("\(count)")
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Tells the user whether receipts are backed up to iCloud.
struct SyncStatusFooter: View {
    private var iCloudAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    var body: some View {
        Label(
            iCloudAvailable
                ? L("Účtenky a složky se zálohují do iCloudu a synchronizují mezi tvými zařízeními.",
                    "Receipts and folders are backed up to iCloud and synced across your devices.")
                : L("iCloud není zapnutý, účtenky jsou jen v tomto telefonu. Zapni iCloud v Nastavení.",
                    "iCloud is off, so receipts are only on this phone. Turn on iCloud in Settings."),
            systemImage: iCloudAvailable ? "icloud" : "icloud.slash"
        )
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }
}

struct PurchaseRow: View {
    let purchase: Purchase
    var showFolder = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(purchase.productName.isEmpty ? L("Bez názvu", "Untitled") : purchase.productName)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(AppFormat.remaining(days: purchase.daysRemaining))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badgeColor.opacity(0.15), in: Capsule())
                .foregroundStyle(badgeColor)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(purchase.storeName.isEmpty ? AppFormat.date(purchase.purchaseDate) : purchase.storeName)
        if showFolder, let folder = purchase.folder { parts.append(folder.name) }
        return parts.joined(separator: " · ")
    }

    private var badgeColor: Color {
        switch purchase.status {
        case .expiringSoon: .orange
        case .active: .green
        case .expired: .secondary
        }
    }
}
