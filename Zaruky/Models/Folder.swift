import Foundation
import SwiftData

/// A user-made folder for receipts (e.g. "Elektronika", "Domácnost").
/// All properties have defaults and the relationship is optional, as CloudKit sync requires.
@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Purchase.folder)
    var purchases: [Purchase]? = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    var purchaseCount: Int { purchases?.count ?? 0 }
}

/// Which receipts the main list shows.
enum FolderFilter: Hashable {
    case all
    case unfiled
    case folder(UUID)

    func matches(_ purchase: Purchase) -> Bool {
        switch self {
        case .all: true
        case .unfiled: purchase.folder == nil
        case .folder(let id): purchase.folder?.id == id
        }
    }
}
