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
    @State private var receiptSource: ImageSource?
    @State private var notificationsDenied = false
    @Environment(\.scenePhase) private var scenePhase

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
                if notificationsDenied && AppSettings.remindersOn && purchase.status != .expired {
                    remindersOffCard
                }
                infoCard
                if !purchase.notes.isEmpty { notesCard }
                receiptCard
                AttachmentsCard(purchase: purchase)
                claimTip
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(purchase.productName.isEmpty ? L("Detail", "Details", "Details") : purchase.productName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L("Upravit", "Edit", "Bearbeiten")) { showEdit = true }
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
        .alert(L("Smazat účtenku?", "Delete receipt?", "Beleg löschen?"), isPresented: $confirmDelete) {
            Button(L("Zrušit", "Cancel", "Abbrechen"), role: .cancel) {}
            Button(L("Smazat", "Delete", "Löschen"), role: .destructive) { delete() }
        } message: {
            Text(L("Účtenka i připomínka zmizí ze všech tvých zařízení.", "The receipt and its reminder are removed from all your devices.", "Der Beleg und seine Erinnerung werden von allen deinen Geräten entfernt."))
        }
        .imageSourcePicker($receiptSource) { setReceipt($0) }
        .task(id: scenePhase) {
            if scenePhase == .active { notificationsDenied = await NotificationService.isDenied() }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 10) {
            ProductTile(name: purchase.productName, status: purchase.status, size: 72)
            Text(purchase.productName.isEmpty ? L("Bez názvu", "Untitled", "Ohne Namen") : purchase.productName)
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(headerAccessibility)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private var headerAccessibility: String {
        var parts: [String] = []
        if !purchase.storeName.isEmpty { parts.append(L("Obchod \(purchase.storeName)", "Store \(purchase.storeName)", "Geschäft \(purchase.storeName)")) }
        if let folder = purchase.folder { parts.append(L("složka \(folder.name)", "folder \(folder.name)", "Ordner \(folder.name)")) }
        return parts.joined(separator: ", ")
    }

    /// Reminders are on in the app, but iOS won't deliver them.
    private var remindersOffCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Upozornění jsou v iOS vypnutá, takže připomínka konce záruky nepřijde.", "Notifications are off in iOS, so the warranty reminder won't arrive.", "Mitteilungen sind in iOS aus, die Garantie-Erinnerung kommt also nicht an."))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(L("Zapnout v Nastavení", "Turn on in Settings", "In Einstellungen einschalten"))
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .card()
    }

    private var statusCard: some View {
        let status = purchase.status
        let days = purchase.daysRemaining
        return HStack(spacing: 18) {
            ZStack {
                WarrantyRing(remaining: 1 - purchase.elapsedFraction, color: status.color, lineWidth: 9)
                VStack(spacing: 0) {
                    Text(ringValue(days))
                        .font(.title.bold())
                        .fontDesign(.rounded)
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
            infoRow(L("Koupeno", "Bought", "Gekauft"), AppFormat.date(purchase.purchaseDate), symbol: "calendar")
            Divider().padding(.leading, 52)
            infoRow(L("Záruka do", "Warranty until", "Garantie bis"), AppFormat.date(purchase.warrantyEndDate), symbol: "calendar.badge.checkmark")
            Divider().padding(.leading, 52)
            infoRow(L("Délka záruky", "Warranty length", "Garantiedauer"), AppFormat.warrantyLength(months: purchase.warrantyMonths), symbol: "shield.lefthalf.filled")
            Divider().padding(.leading, 52)
            infoRow(L("Cena", "Price", "Preis"), AppFormat.price(purchase.price, currency: purchase.currencyCode), symbol: "creditcard")
            if !purchase.serialNumber.isEmpty {
                Divider().padding(.leading, 52)
                serialRow
            }
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

    private var serialRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "barcode")
                .font(.body)
                .foregroundStyle(Theme.brand)
                .frame(width: 28)
            Text(L("Sériové číslo", "Serial number", "Seriennummer"))
                .foregroundStyle(.secondary)
            Spacer()
            Text(purchase.serialNumber)
                .font(.body.monospaced())
                .fontWeight(.medium)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contextMenu {
            Button {
                UIPasteboard.general.string = purchase.serialNumber
            } label: {
                Label(L("Kopírovat", "Copy", "Kopieren"), systemImage: "doc.on.doc")
            }
        }
    }

    /// Receipt first, then the warranty card and other pictures, for the claim share sheet.
    private var claimImages: [Image] {
        let extra = purchase.sortedAttachments.compactMap { $0.imageData.flatMap(UIImage.init(data:)) }
        return ([receiptImage].compactMap { $0 } + extra).map { Image(uiImage: $0) }
    }

    /// Text that goes with the pictures, so the store has the details in one message.
    private var claimMessage: String {
        var parts = [purchase.productName]
        let bought = AppFormat.date(purchase.purchaseDate)
        parts.append(purchase.storeName.isEmpty ? L("koupeno \(bought)", "bought on \(bought)", "gekauft am \(bought)")
                                                : L("koupeno \(bought) v \(purchase.storeName)", "bought on \(bought) at \(purchase.storeName)", "gekauft am \(bought) bei \(purchase.storeName)"))
        if !purchase.serialNumber.isEmpty {
            parts.append(L("sériové číslo \(purchase.serialNumber)", "serial number \(purchase.serialNumber)", "Seriennummer \(purchase.serialNumber)"))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ") + "."
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("Poznámka", "Note", "Notiz"), systemImage: "note.text")
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
                Text(L("Účtenka", "Receipt", "Beleg"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button { showImage = true } label: {
                    Image(uiImage: receiptImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220, alignment: .top)
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
                .accessibilityLabel(L("Zobrazit účtenku", "View receipt", "Beleg ansehen"))

                claimShareButton
            }
            .padding(14)
            .card()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Menu {
                    ImageSourceButtons { receiptSource = $0 }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.title3)
                            .foregroundStyle(Theme.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Přidat fotku účtenky", "Add a receipt photo", "Belegfoto hinzufügen"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.brand)
                            Text(L("K tomuhle nákupu ji zatím nemáš. Při reklamaci se hodí.", "This purchase doesn't have one yet. It helps with a claim.", "Zu diesem Kauf gibt es noch keins. Es hilft bei einer Reklamation."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // The details, and any other documents, can still go to the store.
                claimShareButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card()
        }
    }

    /// Sends the receipt, the other documents and the details to the store.
    /// Without any picture it still sends the details as text.
    @ViewBuilder
    private var claimShareButton: some View {
        if claimImages.isEmpty {
            ShareLink(item: claimMessage, subject: Text(L("Reklamace – ", "Claim – ", "Reklamation – ") + purchase.productName)) {
                claimLabel(L("Poslat údaje k reklamaci", "Send details for a claim", "Angaben für Reklamation senden"))
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
            imageShareLink
        }
    }

    private func claimLabel(_ title: String) -> some View {
        Label(title, systemImage: "square.and.arrow.up")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private var imageShareLink: some View {
        ShareLink(
            items: claimImages,
            subject: Text(L("Reklamace – ", "Claim – ", "Reklamation – ") + purchase.productName),
            message: Text(claimMessage),
            preview: { image in SharePreview(L("Reklamace – ", "Claim – ", "Reklamation – ") + purchase.productName, image: image) }
        ) {
            claimLabel(receiptImage == nil ? L("Poslat doklady k reklamaci", "Send documents for a claim", "Dokumente für Reklamation senden")
                                           : L("Poslat účtenku k reklamaci", "Send receipt for a claim", "Beleg für Reklamation senden"))
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }

    @ViewBuilder
    private var claimTip: some View {
        if purchase.status != .expired {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Theme.amber)
                Text(L("Reklamaci uplatníš u prodejce, kde jsi zboží koupil. Stačí účtenka a popis závady, prodejce má na vyřízení 30 dní.", "Make a claim with the store you bought it from. The receipt and a description of the fault are enough; the store has 30 days to resolve it.", "Reklamiere beim Geschäft, in dem du gekauft hast. Der Beleg und eine Beschreibung des Mangels reichen. Die genauen Fristen hängen vom Land ab."))
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
                    if purchase.folder == nil { Label(L("Bez složky", "No folder", "Kein Ordner"), systemImage: "checkmark") }
                    else { Text(L("Bez složky", "No folder", "Kein Ordner")) }
                }
                ForEach(folders) { folder in
                    Button { move(to: folder) } label: {
                        if purchase.folder?.id == folder.id { Label(folder.name, systemImage: "checkmark") }
                        else { Text(folder.name) }
                    }
                }
            } label: {
                Label(L("Přesunout do složky", "Move to folder", "In Ordner verschieben"), systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: {
                Label(L("Smazat", "Delete", "Löschen"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(L("Další akce", "More actions", "Weitere Aktionen"))
    }

    // MARK: Text

    private var statusTitle: String {
        switch purchase.status {
        case .active: L("Kryto zárukou", "Covered", "Abgedeckt")
        case .expiringSoon: L("Záruka brzy končí", "Warranty ending soon", "Garantie endet bald")
        case .expired: L("Záruka skončila", "Warranty has ended", "Garantie ist abgelaufen")
        }
    }

    private var statusText: String {
        let days = purchase.daysRemaining
        let end = AppFormat.date(purchase.warrantyEndDate)
        if days < 0 { return L("Skončila \(end).", "It ended on \(end).", "Sie ist am \(end) abgelaufen.") }
        if days == 0 { return L("Končí dnes. Pokud něco nefunguje, reklamuj to ještě dnes.", "It ends today. If something is wrong, make a claim today.", "Sie endet heute. Wenn etwas nicht stimmt, reklamiere noch heute.") }
        if purchase.status == .expiringSoon {
            return L("Končí \(end). Zkontroluj, jestli všechno funguje, dokud je čas.", "It ends on \(end). Check everything still works while there's time.", "Sie endet am \(end). Prüf, ob alles noch funktioniert, solange Zeit ist.")
        }
        guard AppSettings.remindersOn, !notificationsDenied else { return L("Do \(end).", "Until \(end).", "Bis \(end).") }
        return L("Do \(end). Připomeneme se \(AppFormat.days(NotificationService.daysBefore)) předem.", "Until \(end). We'll remind you \(AppFormat.days(NotificationService.daysBefore)) before.", "Bis \(end). Wir erinnern dich \(AppFormat.days(NotificationService.daysBefore)) vorher.")
    }

    /// Whole years only when the months divide evenly, so 26 months never reads as "2 years".
    private func showsYears(_ months: Int) -> Bool { months >= 24 && months % 12 == 0 }

    private func ringValue(_ days: Int) -> String {
        if days < 0 { return "0" }
        if days <= 60 { return "\(days)" }
        let months = Int((Double(days) / 30.44).rounded())
        return showsYears(months) ? "\(months / 12)" : "\(months)"
    }

    private func ringUnit(_ days: Int) -> String {
        if days < 0 { return AppFormat.word(0, .day) }
        if days <= 60 { return AppFormat.word(days, .day) }
        let months = Int((Double(days) / 30.44).rounded())
        if !showsYears(months) { return AppFormat.word(months, .month) }
        return AppFormat.word(months / 12, .year)
    }

    // MARK: Actions

    private func setReceipt(_ image: UIImage) {
        purchase.receiptImageData = image.storageJPEG()
        try? modelContext.save()
    }

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

    var body: some View {
        NavigationStack {
            ZoomableImageView(image: image)
                .ignoresSafeArea(edges: .bottom)
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Hotovo", "Done", "Fertig")) { dismiss() }
                    }
                }
        }
    }
}

/// Photo-style viewer: opens with the whole receipt fitting the width (tall invoices scroll),
/// pinch to zoom in and out, pan, double tap to zoom in or back.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomScrollView {
        ZoomScrollView(image: image)
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {}
}

final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private var lastBounds: CGSize = .zero

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        delegate = self
        backgroundColor = .black
        showsHorizontalScrollIndicator = false
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        imageView.frame = CGRect(origin: .zero, size: image.size)
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Zoom at which the whole width fits; very wide images also fit their height.
    private var fitScale: CGFloat {
        let size = imageView.image?.size ?? .zero
        guard size.width > 0, size.height > 0, bounds.width > 0 else { return 1 }
        let widthScale = bounds.width / size.width
        let heightScale = bounds.height / size.height
        // Tall receipts: fill the width and scroll. Wide photos: show them whole.
        return size.height * widthScale > bounds.height ? widthScale : min(widthScale, heightScale)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastBounds, bounds.width > 0 else {
            centerImage()
            return
        }
        let wasAtFit = lastBounds == .zero || abs(zoomScale - minimumZoomScale) < 0.001
        lastBounds = bounds.size
        let fit = fitScale
        minimumZoomScale = fit
        maximumZoomScale = max(fit * 6, 1)
        if wasAtFit || zoomScale < fit {
            zoomScale = fit
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        }
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    /// Keeps the image centred while it's smaller than the screen.
    private func centerImage() {
        let content = imageView.frame.size
        let x = max(0, (bounds.width - content.width) / 2)
        let y = max(0, (bounds.height - content.height) / 2)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.05 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let target = min(minimumZoomScale * 2.5, maximumZoomScale)
            let size = CGSize(width: bounds.width / target, height: bounds.height / target)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }
}
