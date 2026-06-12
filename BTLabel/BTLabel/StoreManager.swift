import Foundation
import Combine
import CryptoKit
import StoreKit
import PTouchKit

/// Owns the one-time "unlock" in-app purchase. The app is free with a print-limited
/// trial; buying the unlock removes the print limit. Everything else (design,
/// favorites, history) is always available.
@MainActor
final class StoreManager: ObservableObject {
    /// Non-consumable product id (configure the same id in App Store Connect and in
    /// the local .storekit test configuration).
    static let unlockProductID = "com.popperbiz.BTLabel.unlock"

    /// Public key for verifying complimentary "redeem-by" keys (the private key is
    /// kept out of the repo; mint keys with `swift run btkeygen`).
    static let compPublicKeyB64 = "QbuFX8KvpIRyFLW62f0gD915RFXqN0Zy1cYZ5HiIUaQ="

    @Published private(set) var product: Product?
    /// Entitlement from a StoreKit purchase.
    @Published private(set) var purchased = false
    /// Lifetime unlock from redeeming a complimentary key (persisted locally).
    @Published private(set) var compUnlocked = UserDefaults.standard.bool(forKey: "compUnlocked")
    /// True once a product fetch has completed (regardless of success), so the UI
    /// can distinguish "still loading" from "store unavailable".
    @Published private(set) var loaded = false
    @Published var purchaseError: String?

    /// Unlocked by either a purchase or a redeemed comp key.
    var isUnlocked: Bool { purchased || compUnlocked }

    enum RedeemResult { case success, expired, invalid }

    /// Redeem a complimentary key. Valid only if its signature checks out and the
    /// current date is before its deadline; success unlocks for life.
    func redeem(_ key: String) -> RedeemResult {
        guard let pubData = Data(base64Encoded: Self.compPublicKeyB64),
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData),
              let deadline = CompKey.verifiedDeadline(key, publicKey: pub) else { return .invalid }
        guard Date() < deadline else { return .expired }
        compUnlocked = true
        UserDefaults.standard.set(true, forKey: "compUnlocked")
        return .success
    }

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
        loaded = true
    }

    /// Reflect any existing entitlement (prior purchase, restored, or synced).
    func refreshEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.unlockProductID, t.revocationDate == nil {
                unlocked = true
            }
        }
        purchased = unlocked
    }

    func purchase() async {
        guard let product else { return }
        purchaseError = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    purchased = true
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
