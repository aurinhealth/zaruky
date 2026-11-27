import SwiftUI

struct PaywallView: View {
    @Environment(PurchaseStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text(L("Záruky navždy", "Warranties forever"))
                    .font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 12) {
                    Label(L("Neomezený počet účtenek", "Unlimited receipts"), systemImage: "infinity")
                    Label(L("Zaplatíš jednou, žádné předplatné", "Pay once, no subscription"), systemImage: "creditcard")
                    Label(L("Data jen v tvém iCloudu, nikde jinde", "Your data stays in your own iCloud"), systemImage: "lock.icloud")
                    Label(L("Funguje i v Rodinném sdílení", "Works with Family Sharing"), systemImage: "person.2")
                }
                .font(.body)
                Spacer()

                if store.isUnlocked {
                    Text(L("Odemčeno, díky!", "Unlocked, thank you!")).font(.headline)
                    Button(L("Hotovo", "Done")) { dismiss() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        Task {
                            await store.buy()
                            if store.isUnlocked { dismiss() }
                        }
                    } label: {
                        Group {
                            if store.isPurchasing {
                                ProgressView()
                            } else if let product = store.product {
                                Text(L("Odemknout za ", "Unlock for ") + product.displayPrice)
                            } else {
                                Text(L("Načítám…", "Loading…"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.product == nil || store.isPurchasing)

                    Button(L("Obnovit nákup", "Restore purchase")) {
                        Task { await store.restore() }
                    }
                    .font(.footnote)
                }

                if let error = store.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Zavřít", "Close")) { dismiss() }
                }
            }
            .task {
                if store.product == nil { await store.loadProduct() }
            }
        }
    }
}
