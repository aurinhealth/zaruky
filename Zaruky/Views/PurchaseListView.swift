import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

/// What the add/edit form is opened with.
struct FormContext: Identifiable {
    let id = UUID()
    var image: UIImage?
    /// Text taken straight from a PDF, used instead of OCR.
    var text: String? = nil
}

struct PurchaseListView: View {
    @Environment(PurchaseStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Purchase.purchaseDate, order: .reverse) private var purchases: [Purchase]
    @Query(sort: \Folder.createdAt) private var folderQuery: [Folder]

    @State private var path: [Purchase] = []
    @State private var searchText = ""
    @State private var filter: FolderFilter = .all
    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    /// Receipts picked from Files that are waiting for their form, one after another.
    @State private var importQueue: [FormContext] = []
    @State private var importNote: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var formContext: FormContext?
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var showDemoViewer = false
    @State private var showExpired = true
    /// "Remind you before the warranty ends?" after the first saved receipt.
    @State private var askReminders = false

    // Folder editing
    @State private var showFolderEditor = false
    @State private var editingFolder: Folder?
    @State private var folderName = ""
    @State private var folderToDelete: Folder?
    @State private var purchaseToDelete: Purchase?

    private var folders: [Folder] {
        folderQuery.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedFolder: Folder? {
        if case .folder(let id) = filter { return folders.first { $0.id == id } }
        return nil
    }

    /// Changes whenever something the widgets show changes.
    private var widgetSignature: [String] {
        purchases.map { "\($0.id)|\($0.productName)|\($0.storeName)|\($0.warrantyEndDate.timeIntervalSince1970)|\($0.price ?? -1)|\($0.currencyCode)" }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
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
        NavigationStack(path: $path) {
            Group {
                if purchases.isEmpty && folders.isEmpty {
                    WelcomeView(onScan: { start(.scan) },
                                onPhoto: { start(.photo) },
                                onFiles: { start(.files) },
                                onManual: { start(.manual) })
                } else {
                    content
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(L("Nastavení", "Settings"))
                }
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
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: FileImport.contentTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        .onOpenURL { url in
            // A widget opens a receipt's detail.
            if let id = WidgetBridge.purchaseID(from: url) {
                if let purchase = purchases.first(where: { $0.id == id }) { path = [purchase] }
                return
            }
            // "Open in Záruky" / "Copy to Záruky" from the share sheet in Files, Mail, Safari…
            guard url.isFileURL else { return }
            guard store.canAdd(currentCount: purchases.count) else { showPaywall = true; return }
            importFiles([url])
        }
        .sheet(item: $formContext, onDismiss: formClosed) { context in
            PurchaseFormView(purchase: nil, image: context.image, initialFolder: selectedFolder,
                             prefilledText: context.text,
                             queueNote: importQueue.isEmpty ? nil
                                : L("Další účtenky čekají: \(importQueue.count)", "More receipts waiting: \(importQueue.count)"))
        }
        .alert(L("Import ze Souborů", "Import from Files"),
               isPresented: Binding(get: { importNote != nil }, set: { if !$0 { importNote = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importNote ?? "")
        }
        .alert(L("Připomenout konec záruky?", "Remind you when the warranty ends?"), isPresented: $askReminders) {
            Button(L("Připomínat", "Remind me")) { allowReminders() }
            Button(L("Teď ne", "Not now"), role: .cancel) { declineReminders() }
        } message: {
            Text(L("Ozvu se \(AppFormat.days(AppSettings.reminderDays)) předtím, než záruka skončí, ať stihneš případnou reklamaci.",
                   "You'll hear from me \(AppFormat.days(AppSettings.reminderDays)) before a warranty ends, so there's time for a claim."))
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(usedCount: purchases.count)
        }
        .fullScreenCover(isPresented: $showDemoViewer) {
            ReceiptImageViewer(image: DemoMode.sampleInvoice)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
        .alert(
            L("Smazat účtenku?", "Delete receipt?"),
            isPresented: Binding(get: { purchaseToDelete != nil }, set: { if !$0 { purchaseToDelete = nil } })
        ) {
            Button(L("Zrušit", "Cancel"), role: .cancel) { purchaseToDelete = nil }
            Button(L("Smazat", "Delete"), role: .destructive) { deletePurchase() }
        } message: {
            Text(L("Účtenka i připomínka zmizí ze všech tvých zařízení.",
                   "The receipt and its reminder are removed from all your devices."))
        }
        .task(id: purchases.count) { await NotificationService.sync(with: purchases) }
        .onChange(of: widgetSignature, initial: true) { _, _ in WidgetBridge.update(with: purchases) }
        .task { openDemoScreen() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await NotificationService.sync(with: purchases) } }
            if phase == .background { WidgetBridge.update(with: purchases) }
        }
        .onChange(of: folders.map(\.id)) { _, ids in
            // The selected folder may have been deleted, here or on another device.
            if case .folder(let id) = filter, !ids.contains(id) { filter = .all }
        }
    }

    // MARK: Main content

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                FolderBar(
                    folders: folders,
                    purchases: purchases,
                    selection: $filter,
                    onNew: { startNewFolder() },
                    onRename: { startRename($0) },
                    onDelete: { folderToDelete = $0 }
                )
                .padding(.horizontal, -Theme.pagePadding)

                if filter == .all && !isSearching && !purchases.isEmpty {
                    SummaryCard(purchases: purchases)
                        .padding(.bottom, store.isUnlocked ? 8 : 0)
                    // Up top, so it isn't hidden under the bottom bar when the list is short.
                    if !store.isUnlocked {
                        FreeLimitCard(used: purchases.count) { showPaywall = true }
                            .padding(.bottom, 8)
                    }
                }

                ForEach(WarrantyStatus.allCases) { status in
                    let items = filtered.filter { $0.status == status }
                    if !items.isEmpty {
                        sectionHeader(status, count: items.count)
                        if status != .expired || showExpired || isSearching {
                            ForEach(items) { purchase in
                                NavigationLink(value: purchase) {
                                    PurchaseCard(purchase: purchase, showFolder: filter == .all)
                                }
                                .buttonStyle(CardButtonStyle())
                                .contextMenu { contextMenu(for: purchase) }
                            }
                        }
                    }
                }

                if filtered.isEmpty {
                    emptyFilterState
                        .padding(.top, 40)
                }

                SyncStatusFooter()
                    .padding(.top, 8)
            }
            .padding(.horizontal, Theme.pagePadding)
            // Keeps the last card clear of the search and scan bar.
            .padding(.bottom, 96)
            .animation(.snappy, value: filter)
            .animation(.snappy, value: showExpired)
        }
        .searchable(text: $searchText, prompt: L("Hledat produkt nebo obchod", "Search product or store"))
        .searchToolbarBehavior(.minimize)
        .toolbar {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) { scanButton }
        }
    }

    private func sectionHeader(_ status: WarrantyStatus, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
            Text(status.title)
            Text("\(count)")
                .foregroundStyle(.secondary)
            Spacer()
            if status == .expired && !isSearching {
                Button {
                    showExpired.toggle()
                } label: {
                    Text(showExpired ? L("Skrýt", "Hide") : L("Zobrazit", "Show"))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .font(.subheadline)
            }
        }
        .font(.headline)
        .padding(.top, 14)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }

    private var scanButton: some View {
        Button { start(.scan) } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.viewfinder")
                Text(L("Naskenovat účtenku", "Scan a receipt"))
            }
            .font(.headline)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.glassProminent)
        // Toolbar items don't inherit the app tint, so name the asset colour directly.
        .tint(Color("AccentColor"))
        .accessibilityLabel(L("Naskenovat účtenku", "Scan a receipt"))
    }

    @ViewBuilder
    private var emptyFilterState: some View {
        if isSearching {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label(L("Složka je prázdná", "This folder is empty"), systemImage: "folder")
            } description: {
                Text(L("Naskenuj sem účtenku, nebo sem nějakou přesuň podržením prstu na kartě.",
                       "Scan a receipt into it, or move one here by long-pressing its card."))
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for purchase: Purchase) -> some View {
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
        Divider()
        Button(role: .destructive) {
            purchaseToDelete = purchase
        } label: {
            Label(L("Smazat", "Delete"), systemImage: "trash")
        }
    }

    private var addMenu: some View {
        Menu {
            Button { start(.scan) } label: { Label(L("Naskenovat", "Scan"), systemImage: "doc.viewfinder") }
            Button { start(.photo) } label: { Label(L("Vybrat z Fotek", "Choose from Photos"), systemImage: "photo") }
            Button { start(.files) } label: { Label(L("Nahrát ze Souborů", "Import from Files"), systemImage: "folder") }
            Button { start(.manual) } label: { Label(L("Zadat ručně", "Enter manually"), systemImage: "square.and.pencil") }
            Divider()
            Button { startNewFolder() } label: { Label(L("Nová složka", "New folder"), systemImage: "folder.badge.plus") }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(L("Přidat", "Add"))
    }

    private enum AddSource { case scan, photo, files, manual }

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
        case .files:
            showFileImporter = true
        case .manual:
            formContext = FormContext(image: nil)
        }
    }

    // MARK: Files

    /// Reads the picked files and opens the form for each, one after another.
    /// Respects the free limit: only as many as still fit are imported.
    private func importFiles(_ urls: [URL]) {
        let loaded = urls.compactMap(FileImport.load)
        let failed = urls.count - loaded.count
        let room = store.isUnlocked ? loaded.count : max(PurchaseStore.freeLimit - purchases.count, 0)
        let accepted = Array(loaded.prefix(room))
        let overLimit = loaded.count - accepted.count

        var notes: [String] = []
        if failed > 0 {
            notes.append(L("\(AppFormat.receipts(failed)) se nepodařilo otevřít.", "Couldn't open \(AppFormat.receipts(failed))."))
        }
        if overLimit > 0 {
            notes.append(L("\(AppFormat.receipts(overLimit)) se nevešlo do verze zdarma.",
                           "\(AppFormat.receipts(overLimit)) didn't fit in the free version."))
        }

        guard !accepted.isEmpty else {
            if overLimit > 0 { showPaywall = true } else if !notes.isEmpty { importNote = notes.joined(separator: " ") }
            return
        }
        if !notes.isEmpty { importNote = notes.joined(separator: " ") }
        importQueue = accepted.dropFirst().map { FormContext(image: $0.image, text: $0.text) }
        formContext = FormContext(image: accepted[0].image, text: accepted[0].text)
    }

    private func formClosed() {
        if importQueue.isEmpty {
            Task { await offerReminders() }
        } else {
            showNextImport()
        }
    }

    /// Asks about reminders once the first receipt is saved, instead of at first launch:
    /// by then it's clear what they're for, and iOS only shows its own prompt once.
    private func offerReminders() async {
        guard !DemoMode.isOn, !purchases.isEmpty, AppSettings.remindersOn,
              await NotificationService.notAskedYet() else { return }
        try? await Task.sleep(for: .milliseconds(450))
        askReminders = true
    }

    private func allowReminders() {
        Task {
            await NotificationService.requestAuthorization()
            await NotificationService.sync(with: purchases)
        }
    }

    private func declineReminders() {
        // Settings then shows reminders off; turning them on there asks iOS again.
        UserDefaults.standard.set(false, forKey: AppSettings.Key.remindersOn)
        Task { await NotificationService.sync(with: purchases) }
    }

    private func showNextImport() {
        guard !importQueue.isEmpty else { return }
        let next = importQueue.removeFirst()
        Task { @MainActor in
            // Let the previous sheet finish closing before the next one opens.
            try? await Task.sleep(for: .milliseconds(450))
            formContext = next
        }
    }

    private func openDemoScreen() {
        switch DemoMode.screen {
        case "detail":
            if let first = purchases.first(where: { $0.status == .expiringSoon }) ?? purchases.first {
                path = [first]
            }
        case "paywall": showPaywall = true
        case "settings": showSettings = true
        case "viewer": showDemoViewer = true
        case "form": formContext = FormContext(image: nil)
        case "folder": filter = folders.first.map { .folder($0.id) } ?? .all
        default: break
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

    private func deletePurchase() {
        guard let purchase = purchaseToDelete else { return }
        NotificationService.cancel(for: purchase)
        modelContext.delete(purchase)
        try? modelContext.save()
        purchaseToDelete = nil
    }
}

/// Press feedback for cards that act as links.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Summary

/// At-a-glance answer to "am I covered?": how much money is under warranty and what needs attention.
struct SummaryCard: View {
    let purchases: [Purchase]

    private var active: [Purchase] { purchases.filter { $0.status != .expired } }
    private var soon: [Purchase] { purchases.filter { $0.status == .expiringSoon } }
    @AppStorage(AppSettings.Key.currency) private var currency = AppSettings.defaultCurrency
    /// Sums only receipts in the default currency, so different currencies are never added together.
    private var protectedValue: Double {
        active.filter { $0.currencyCode == currency }.compactMap(\.price).reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Pod zárukou máš", "Under warranty"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text(AppFormat.price(protectedValue, currency: currency))
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                pill(value: active.count, label: L("platných", "active"), symbol: "checkmark.shield.fill")
                pill(value: soon.count, label: L("brzy končí", "ending soon"),
                     symbol: "exclamationmark.circle.fill", highlight: !soon.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.06, green: 0.50, blue: 0.37),
                                              Color(red: 0.02, green: 0.35, blue: 0.26)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 120))
                        .foregroundStyle(.white.opacity(0.08))
                        .offset(x: 20, y: -16)
                        .clipped()
                }
                .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .shadow(color: Color(red: 0.03, green: 0.42, blue: 0.31).opacity(0.25), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    private func pill(value: Int, label: String, symbol: String, highlight: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(highlight ? Theme.amber : .white)
            Text("\(value)").fontWeight(.bold)
            Text(label)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.white.opacity(highlight ? 0.22 : 0.15), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Card

struct PurchaseCard: View {
    let purchase: Purchase
    var showFolder = false

    var body: some View {
        let status = purchase.status
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ProductTile(name: purchase.productName, status: status)
                VStack(alignment: .leading, spacing: 3) {
                    Text(purchase.productName.isEmpty ? L("Bez názvu", "Untitled") : purchase.productName)
                        .font(.headline)
                        .foregroundStyle(status == .expired ? .secondary : .primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(AppFormat.remaining(days: purchase.daysRemaining))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(status == .expired ? Color.secondary : status.color)
                    if let price = purchase.price {
                        Text(AppFormat.price(price, currency: purchase.currencyCode))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if status != .expired {
                ProgressBar(value: 1 - purchase.elapsedFraction, color: status.color)
            }
        }
        .padding(14)
        .card()
        .contentShape(.rect(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("Otevře detail účtenky", "Opens the receipt"))
    }

    private var subtitle: String {
        var parts: [String] = []
        if !purchase.storeName.isEmpty { parts.append(purchase.storeName) }
        if showFolder, let folder = purchase.folder { parts.append(folder.name) }
        if parts.isEmpty { parts.append(AppFormat.date(purchase.purchaseDate)) }
        return parts.joined(separator: " · ")
    }
}

/// Thin bar showing how much warranty is left.
struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.14))
                Capsule().fill(color.gradient)
                    .frame(width: max(geo.size.width * min(max(value, 0), 1), 6))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Free limit

struct FreeLimitCard: View {
    let used: Int
    var onUnlock: () -> Void

    private var total: Int { PurchaseStore.freeLimit }
    private var left: Int { max(total - used, 0) }

    var body: some View {
        Button(action: onUnlock) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(Theme.amber)
                    .frame(width: 44, height: 44)
                    .background(Theme.amber.opacity(0.15), in: .rect(cornerRadius: Theme.tileRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(left > 0
                         ? L("Zdarma ještě \(AppFormat.receipts(left))", "\(AppFormat.receipts(left)) left for free")
                         : L("Využil jsi všech \(total) účtenek zdarma", "You've used all \(total) free receipts"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        ForEach(0..<total, id: \.self) { i in
                            Capsule()
                                .fill(i < used ? Theme.amber : Color(.tertiarySystemFill))
                                .frame(height: 5)
                        }
                    }
                }
                Spacer(minLength: 4)
                Text(L("Odemknout", "Unlock"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.brand)
            }
            .padding(14)
            .card()
        }
        .buttonStyle(CardButtonStyle())
    }
}

// MARK: - Folders

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
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(L("Vše", "All"), count: purchases.count, icon: "square.stack.fill", filter: .all)
                ForEach(folders) { folder in
                    chip(folder.name, count: folder.purchaseCount, icon: "folder.fill", filter: .folder(folder.id))
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
                    chip(L("Bez složky", "No folder"), count: unfiledCount, icon: "tray.fill", filter: .unfiled)
                }
                Button(action: onNew) {
                    Image(systemName: "folder.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L("Nová složka", "New folder"))
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func chip(_ title: String, count: Int, icon: String, filter: FolderFilter) -> some View {
        let isSelected = selection == filter
        return Button {
            withAnimation(.snappy) { selection = filter }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title).lineLimit(1)
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.black.opacity(0.22) : Color(.tertiarySystemFill), in: Capsule())
            }
            .font(.subheadline.weight(.semibold))
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(isSelected ? AnyShapeStyle(Theme.brand.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                        in: Capsule())
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .shadow(color: .black.opacity(isSelected ? 0.12 : 0.04), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(AppFormat.receipts(count))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Tells the user whether receipts are backed up to iCloud.
struct SyncStatusFooter: View {
    private var iCloudAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil || DemoMode.isOn }

    var body: some View {
        Label(
            iCloudAvailable
                ? L("Zálohováno v iCloudu, synchronizuje se mezi tvými zařízeními.",
                    "Backed up to iCloud and synced across your devices.")
                : L("iCloud není zapnutý, účtenky jsou jen v tomto telefonu. Zapni iCloud v Nastavení.",
                    "iCloud is off, so receipts are only on this phone. Turn on iCloud in Settings."),
            systemImage: iCloudAvailable ? "checkmark.icloud" : "icloud.slash"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }
}

// MARK: - Welcome (first run)

/// First-run screen: says what the app does in three steps and gets the user to the first scan.
struct WelcomeView: View {
    var onScan: () -> Void
    var onPhoto: () -> Void
    var onFiles: () -> Void
    var onManual: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                    .padding(.top, 12)

                VStack(spacing: 8) {
                    Text(L("Účtenky, které neztratíš", "Receipts you won't lose"))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(L("Vyfoť účtenku a appka ohlídá záruku za tebe. Když se něco rozbije, doklad máš hned po ruce.",
                           "Snap a receipt and the app keeps an eye on the warranty. When something breaks, the proof is right there."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)

                VStack(spacing: 0) {
                    step(1, symbol: "doc.viewfinder", title: L("Naskenuj účtenku", "Scan the receipt"),
                         text: L("Stačí ji vyfotit, ořízne se sama.", "Just take a photo, it crops itself."))
                    Divider().padding(.leading, 64)
                    step(2, symbol: "wand.and.sparkles", title: L("Údaje se vyplní samy", "Details fill themselves in"),
                         text: L("Produkt, obchod, datum i cenu přečte AI přímo v telefonu.",
                                 "On-device AI reads the product, store, date and price."))
                    Divider().padding(.leading, 64)
                    step(3, symbol: "bell.badge.fill", title: L("Připomeneme se včas", "We remind you in time"),
                         text: L("\(AppFormat.days(AppSettings.reminderDays)) předem víš, že záruka končí.",
                                 "You hear from us \(AppFormat.days(AppSettings.reminderDays)) before it ends."))
                }
                .card()

                VStack(spacing: 12) {
                    Button(action: onScan) {
                        Label(L("Naskenovat první účtenku", "Scan your first receipt"), systemImage: "doc.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    HStack(spacing: 10) {
                        sourceButton(L("Z Fotek", "Photos"), symbol: "photo", action: onPhoto)
                        sourceButton(L("Ze Souborů", "Files"), symbol: "folder", action: onFiles)
                        sourceButton(L("Ručně", "Manually"), symbol: "square.and.pencil", action: onManual)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    private func sourceButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
    }

    private var hero: some View {
        ZStack {
            Circle()
                .fill(Theme.brand.opacity(0.10))
                .frame(width: 180, height: 180)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(width: 96, height: 124)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(Color(.tertiarySystemFill)).frame(width: 46, height: 8)
                        Capsule().fill(Color(.tertiarySystemFill)).frame(width: 64, height: 6)
                        Capsule().fill(Color(.tertiarySystemFill)).frame(width: 54, height: 6)
                        Capsule().fill(Color(.tertiarySystemFill)).frame(width: 60, height: 6)
                        Capsule().fill(Theme.brand.opacity(0.7)).frame(width: 36, height: 8).padding(.top, 6)
                    }
                    .padding(16)
                }
                .rotationEffect(.degrees(-7))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Theme.amber)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                .offset(x: 46, y: 46)
        }
        .frame(height: 190)
        .accessibilityHidden(true)
    }

    private func step(_ n: Int, symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.brand)
                .frame(width: 36, height: 36)
                .background(Theme.brand.opacity(0.12), in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}
