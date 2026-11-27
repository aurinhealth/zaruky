import Foundation
import SwiftData

enum WarrantyStatus: Int, CaseIterable, Identifiable {
    case expiringSoon
    case active
    case expired

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .expiringSoon: L("Brzy končí", "Ending soon")
        case .active: L("Platná záruka", "Under warranty")
        case .expired: L("Po záruce", "Expired")
        }
    }
}

@Model
final class Purchase {
    var id: UUID = UUID()
    var productName: String = ""
    var storeName: String = ""
    var purchaseDate: Date = Date()
    var price: Double?
    var currencyCode: String = "CZK"
    var warrantyMonths: Int = 24
    var notes: String = ""
    @Attribute(.externalStorage) var receiptImageData: Data?
    var createdAt: Date = Date()
    var folder: Folder?

    init(
        productName: String,
        storeName: String,
        purchaseDate: Date,
        price: Double?,
        warrantyMonths: Int,
        notes: String = "",
        receiptImageData: Data? = nil,
        folder: Folder? = nil
    ) {
        self.id = UUID()
        self.productName = productName
        self.storeName = storeName
        self.purchaseDate = purchaseDate
        self.price = price
        self.warrantyMonths = warrantyMonths
        self.notes = notes
        self.receiptImageData = receiptImageData
        self.createdAt = Date()
        self.folder = folder
    }

    var warrantyEndDate: Date {
        Calendar.current.date(byAdding: .month, value: warrantyMonths, to: purchaseDate) ?? purchaseDate
    }

    var daysRemaining: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: warrantyEndDate)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }

    var status: WarrantyStatus {
        let days = daysRemaining
        if days < 0 { return .expired }
        if days <= 30 { return .expiringSoon }
        return .active
    }

    /// 0...1, how much of the warranty period has elapsed.
    var elapsedFraction: Double {
        let total = warrantyEndDate.timeIntervalSince(purchaseDate)
        guard total > 0 else { return 1 }
        let elapsed = Date().timeIntervalSince(purchaseDate)
        return min(max(elapsed / total, 0), 1)
    }
}
