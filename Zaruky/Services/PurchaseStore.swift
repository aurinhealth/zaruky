import Foundation
import Observation
import StoreKit

/// StoreKit 2 lifetime unlock. First `freeLimit` receipts are free.
@MainActor
@Observable
final class PurchaseStore {
    static let productID = "cz.zaruky.app.lifetime"
    static let freeLimit = 5

    var product: Product?
    var isUnlocked = false
    var isPurchasing = false
    var errorMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
        Task { [weak self] in
            await self?.loadProduct()
            await self?.refreshEntitlements()
        }
    }

    func canAdd(currentCount: Int) -> Bool {
        isUnlocked || currentCount < Self.freeLimit
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            errorMessage = L("Nepodařilo se načíst nabídku.", "Couldn't load the offer.")
        }
    }

    func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }
        isUnlocked = unlocked
    }

    func buy() async {
        guard let product else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    isUnlocked = true
                }
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = L("Nákup se nezdařil. Zkus to prosím znovu.", "The purchase failed. Please try again.")
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = L("Obnovení nákupu se nezdařilo.", "Couldn't restore the purchase.")
        }
        await refreshEntitlements()
    }
}
