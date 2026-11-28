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
    /// The offer couldn't be loaded from the App Store (offline, or the product isn't available yet).
    var loadFailed = false
    var isLoading = false
    /// True in TestFlight and App Review (StoreKit sandbox), false in the App Store.
    var isSandbox = false
    /// Sandbox only: act as the free version although the purchase is owned, so the
    /// paywall and purchase flow can be shown again (a sandbox purchase can't be undone).
    var simulateFree = UserDefaults.standard.bool(forKey: PurchaseStore.simulateFreeKey) {
        didSet {
            UserDefaults.standard.set(simulateFree, forKey: Self.simulateFreeKey)
            isUnlocked = isEntitled && !simulateFree
        }
    }

    @ObservationIgnored private var isEntitled = false
    private static let simulateFreeKey = "debug.simulateFree"

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
            await self?.loadEnvironment()
            await self?.loadProduct()
            await self?.refreshEntitlements()
        }
    }

    func canAdd(currentCount: Int) -> Bool {
        isUnlocked || currentCount < Self.freeLimit
    }

    private func loadEnvironment() async {
        if case .verified(let transaction)? = try? await AppTransaction.shared {
            isSandbox = transaction.environment != .production
        }
        // Never let the test switch affect App Store customers.
        if !isSandbox && simulateFree { simulateFree = false }
    }

    func loadProduct() async {
        guard !isLoading else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            product = nil
        }
        // An empty answer isn't an error in StoreKit, so treat both the same.
        loadFailed = product == nil
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
        isEntitled = unlocked
        isUnlocked = unlocked && !(isSandbox && simulateFree)
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
                    isEntitled = true
                    simulateFree = false
                    isUnlocked = true
                }
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = L("Nákup se nezdařil. Zkus to prosím znovu.", "The purchase failed. Please try again.", "Der Kauf ist fehlgeschlagen. Bitte versuch es noch einmal.")
        }
    }

    func restore() async {
        simulateFree = false
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = L("Obnovení nákupu se nezdařilo.", "Couldn't restore the purchase.", "Der Kauf ließ sich nicht wiederherstellen.")
        }
        await refreshEntitlements()
    }
}
