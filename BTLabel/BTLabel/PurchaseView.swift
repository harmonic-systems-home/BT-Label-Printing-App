import SwiftUI

/// One-time-purchase unlock sheet. Shown when the free print trial is used up, or
/// opened voluntarily from Settings.
struct PurchaseView: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var c: PrinterController
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput = ""
    @State private var redeemMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "printer.fill.and.paper.fill")
                .font(.system(size: 40)).foregroundStyle(.tint)
            Text("Unlock BTLabel").font(.title2).bold()

            Text(c.printsUsed >= PrinterController.freePrintLimit
                 ? "You've used your \(PrinterController.freePrintLimit) free prints. Unlock unlimited printing with a one-time purchase."
                 : "Buy once for unlimited printing. Designing labels, favorites, and history are always free.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if store.isUnlocked {
                Label("Purchased — thank you!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else if let price = store.priceText {
                Button {
                    Task { await store.purchase(); if store.isUnlocked { dismiss() } }
                } label: {
                    Text("Unlock — \(price)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)

                Button("Restore Purchase") {
                    Task { await store.restore(); if store.isUnlocked { dismiss() } }
                }.buttonStyle(.link)
            } else if !store.loaded {
                ProgressView().controlSize(.small)
                Text("Loading store…").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("The store is unavailable. In Xcode, select a StoreKit configuration (Edit Scheme → Run → Options); on a shipped build this means the App Store is unreachable.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Try Again") { Task { await store.loadProduct() } }
                Button("Restore Purchase") {
                    Task { await store.restore(); if store.isUnlocked { dismiss() } }
                }.buttonStyle(.link)
            }

            if let err = store.purchaseError {
                Text(err).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }

            if !store.isUnlocked {
                Divider()
                Text("Have a community key?").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Paste key", text: $keyInput).textFieldStyle(.roundedBorder)
                    Button("Redeem") {
                        switch store.redeem(keyInput) {
                        case .success: dismiss()
                        case .expired: redeemMessage = "This key has expired."
                        case .invalid: redeemMessage = "That key isn't valid."
                        }
                    }.disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let m = redeemMessage { Text(m).font(.caption).foregroundStyle(.red) }
            }

            Button(store.isUnlocked ? "Done" : "Not now") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 360)
    }
}
