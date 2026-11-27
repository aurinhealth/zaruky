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
    @State private var source: ImageSource?
    @State private var viewing: Attachment?
    @State private var toDelete: Attachment?

    private var attachments: [Attachment] { purchase.sortedAttachments }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Další doklady", "More documents", "Weitere Dokumente"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                addMenu
            }

            if attachments.isEmpty {
                Text(L("Přidej záruční list, fotku výrobku nebo štítek se sériovým číslem. Při reklamaci se hodí.", "Add the warranty card, a photo of the product or its serial number label. They help with a claim.", "Füge den Garantieschein, ein Produktfoto oder das Typenschild hinzu. Das hilft bei einer Reklamation."))
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
        .imageSourcePicker($source) { add($0) }
        .fullScreenCover(item: $viewing) { attachment in
            if let image = attachment.imageData.flatMap(UIImage.init(data:)) {
                ReceiptImageViewer(image: image)
            }
        }
        .alert(L("Smazat doklad?", "Delete this document?", "Dieses Dokument löschen?"),
               isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button(L("Zrušit", "Cancel", "Abbrechen"), role: .cancel) { toDelete = nil }
            Button(L("Smazat", "Delete", "Löschen"), role: .destructive) { deletePending() }
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(AttachmentKind.allCases) { kind in
                Menu {
                    ImageSourceButtons { pendingKind = kind; source = $0 }
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }
        } label: {
            Label(L("Přidat", "Add", "Hinzufügen"), systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel(L("Přidat doklad", "Add a document", "Dokument hinzufügen"))
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
                Label(L("Změnit typ", "Change type", "Typ ändern"), systemImage: "tag")
            }
            Button(role: .destructive) { toDelete = attachment } label: {
                Label(L("Smazat", "Delete", "Löschen"), systemImage: "trash")
            }
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

// MARK: - Picking a picture

/// Where a picture comes from: the document scanner, Photos or Files.
enum ImageSource: Identifiable {
    case scan, photos, files
    var id: Self { self }
}

/// The three menu buttons for picking a picture.
struct ImageSourceButtons: View {
    var pick: (ImageSource) -> Void

    var body: some View {
        Button { pick(.scan) } label: { Label(L("Vyfotit", "Take a photo", "Foto aufnehmen"), systemImage: "camera") }
        Button { pick(.photos) } label: { Label(L("Z Fotek", "From Photos", "Aus Fotos"), systemImage: "photo") }
        Button { pick(.files) } label: { Label(L("Ze Souborů", "From Files", "Aus Dateien"), systemImage: "folder") }
    }
}

/// Presents the scanner, the photo picker or the file importer for the chosen source,
/// and hands back the picture.
struct ImageSourcePicker: ViewModifier {
    @Binding var source: ImageSource?
    var onImage: (UIImage) -> Void
    @State private var photoItem: PhotosPickerItem?

    private func flag(_ kind: ImageSource) -> Binding<Bool> {
        Binding(get: { source == kind }, set: { if !$0, source == kind { source = nil } })
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: flag(.scan)) {
                DocumentScannerView { image in
                    source = nil
                    if let image { onImage(image) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: flag(.photos), selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        onImage(image)
                    }
                    photoItem = nil
                }
            }
            .fileImporter(isPresented: flag(.files), allowedContentTypes: FileImport.contentTypes) { result in
                if case .success(let url) = result, let file = FileImport.load(url) { onImage(file.image) }
            }
            .onChange(of: source) { _, new in
                // No camera (simulator, some iPads): fall back to Photos.
                if new == .scan, !VNDocumentCameraViewController.isSupported { source = .photos }
            }
    }
}

extension View {
    func imageSourcePicker(_ source: Binding<ImageSource?>, onImage: @escaping (UIImage) -> Void) -> some View {
        modifier(ImageSourcePicker(source: source, onImage: onImage))
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
