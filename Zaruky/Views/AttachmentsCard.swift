import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

/// Detail card with the extra pictures of a purchase (warranty card, product photo, serial label):
/// thumbnails to open full screen, and a menu to add one by scanning, from Photos or from Files.
struct AttachmentsCard: View {
    @Environment(\.modelContext) private var modelContext
    let purchase: Purchase

    @State private var pendingKind: AttachmentKind = .warrantyCard
    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var viewing: Attachment?
    @State private var toDelete: Attachment?

    private var attachments: [Attachment] { purchase.sortedAttachments }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Další doklady", "More documents"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                addMenu
            }

            if attachments.isEmpty {
                Text(L("Přidej záruční list, fotku výrobku nebo štítek se sériovým číslem. Při reklamaci se hodí.",
                       "Add the warranty card, a photo of the product or its serial number label. They help with a claim."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(attachments) { attachment in
                            thumbnail(attachment)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
        .padding(14)
        .card()
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { image in
                showScanner = false
                if let image { add(image) }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    add(image)
                }
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: FileImport.contentTypes) { result in
            if case .success(let url) = result, let file = FileImport.load(url) { add(file.image) }
        }
        .fullScreenCover(item: $viewing) { attachment in
            if let image = attachment.imageData.flatMap(UIImage.init(data:)) {
                ReceiptImageViewer(image: image)
            }
        }
        .confirmationDialog(L("Smazat doklad?", "Delete this document?"),
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button(L("Smazat", "Delete"), role: .destructive) { deletePending() }
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(AttachmentKind.allCases) { kind in
                Menu {
                    Button { start(kind, .scan) } label: { Label(L("Vyfotit", "Take a photo"), systemImage: "camera") }
                    Button { start(kind, .photos) } label: { Label(L("Z Fotek", "From Photos"), systemImage: "photo") }
                    Button { start(kind, .files) } label: { Label(L("Ze Souborů", "From Files"), systemImage: "folder") }
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }
        } label: {
            Label(L("Přidat", "Add"), systemImage: "plus")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func thumbnail(_ attachment: Attachment) -> some View {
        Button { viewing = attachment } label: {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let image = attachment.imageData.flatMap(UIImage.init(data:)) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: attachment.kind.symbol)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.tertiarySystemFill))
                    }
                }
                .frame(width: 96, height: 120)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))

                Label(attachment.kind.title, systemImage: attachment.kind.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 96, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attachment.kind.title)
        .contextMenu {
            Menu {
                ForEach(AttachmentKind.allCases) { kind in
                    Button {
                        attachment.kindRaw = kind.rawValue
                        try? modelContext.save()
                    } label: {
                        if attachment.kind == kind { Label(kind.title, systemImage: "checkmark") } else { Text(kind.title) }
                    }
                }
            } label: {
                Label(L("Změnit typ", "Change type"), systemImage: "tag")
            }
            Button(role: .destructive) { toDelete = attachment } label: {
                Label(L("Smazat", "Delete"), systemImage: "trash")
            }
        }
    }

    private enum Source { case scan, photos, files }

    private func start(_ kind: AttachmentKind, _ source: Source) {
        pendingKind = kind
        switch source {
        case .scan:
            if VNDocumentCameraViewController.isSupported { showScanner = true } else { showPhotoPicker = true }
        case .photos: showPhotoPicker = true
        case .files: showFileImporter = true
        }
    }

    private func add(_ image: UIImage) {
        let attachment = Attachment(kind: pendingKind, imageData: image.storageJPEG())
        modelContext.insert(attachment)
        attachment.purchase = purchase
        try? modelContext.save()
    }

    private func deletePending() {
        guard let attachment = toDelete else { return }
        toDelete = nil
        modelContext.delete(attachment)
        try? modelContext.save()
    }
}

extension UIImage {
    /// JPEG for the synced store: at most 2400 px on the long side, which keeps small print readable.
    func storageJPEG(maxSide: CGFloat = 2400) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return jpegData(compressionQuality: 0.7) }
        let scale = maxSide / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}
