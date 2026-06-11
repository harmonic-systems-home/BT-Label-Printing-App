import Foundation
import Combine
import StoreKit

/// Owns the one-time "unlock" in-app purchase. The app is free with a print-limited
/// trial; buying the unlock removes the print limit. Everything else (design,
/// favorites, history) is always available.
@MainActor
final class StoreManager: ObservableObject {
    /// Non-consumable product id (configure the same id in App Store Connect and in
    /// the local .storekit test configuration).
    static let unlockProductID = "com.popperbiz.BTLabel.unlock"

    @Published private(set) var product: Product?
    @Published private(set) var isUnlocked = false
    @Published var purchaseError: String?

    private var updates: Task<Void, Never>?

    init() {
        updates = listenForTransactions()
        Task { await loadProduct(); await refreshEntitlement() }
    }

    deinit { updates?.cancel() }

    /// Localized price for the unlock, or nil while loading.
    var priceText: String? { product?.displayPrice }

    func loadProduct() async {
        product = try? await Product.products(for: [Self.unlockProductID]).first
    }

    /// Reflect any existing entitlement (prior purchase, restored, or synced).
    func refreshEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.unlockProductID, t.revocationDate == nil {
                unlocked = true
            }
        }
        isUnlocked = unlocked
    }

    func purchase() async {
        guard let product else { return }
        purchaseError = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    isUnlocked = true
                }
            case .userCancelled, .pending: break
            @unknown default: break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    /// Restore a previous purchase on a new install / device.
    func restore() async {
        purchaseError = nil
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }
}
