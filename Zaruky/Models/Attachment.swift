import Foundation
import SwiftData

/// What an extra picture of a purchase shows. Stored as text, so a new kind never needs a schema change.
enum AttachmentKind: String, CaseIterable, Identifiable {
    case warrantyCard
    case productPhoto
    case serialLabel
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warrantyCard: L("Záruční list", "Warranty card")
        case .productPhoto: L("Fotka výrobku", "Product photo")
        case .serialLabel: L("Štítek se sériovým číslem", "Serial number label")
        case .other: L("Jiný doklad", "Other document")
        }
    }

    var symbol: String {
        switch self {
        case .warrantyCard: "doc.text"
        case .productPhoto: "camera"
        case .serialLabel: "barcode"
        case .other: "paperclip"
        }
    }
}

/// An extra picture kept with a purchase besides the receipt: a warranty card, a photo of
/// the product or its serial number label. Synced through iCloud like the rest.
/// All properties have defaults and the relationship is optional, as CloudKit sync requires.
@Model
final class Attachment {
    var id: UUID = UUID()
    var kindRaw: String = AttachmentKind.other.rawValue
    @Attribute(.externalStorage) var imageData: Data?
    var createdAt: Date = Date()
    var purchase: Purchase?

    init(kind: AttachmentKind, imageData: Data?) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.imageData = imageData
        self.createdAt = Date()
    }

    var kind: AttachmentKind { AttachmentKind(rawValue: kindRaw) ?? .other }
}
