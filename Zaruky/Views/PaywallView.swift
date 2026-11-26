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
                Text("Záruky navždy")
                    .font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 12) {
                    Label("Neomezený počet účtenek", systemImage: "infinity")
                    Label("Zaplatíš jednou, žádné předplatné", systemImage: "creditcard")
                    Label("Data zůstávají v tvém telefonu", systemImage: "lock.shield")
                    Label("Funguje i v Rodinném sdílení", systemImage: "person.2")
                }
                .font(.body)
                Spacer()

                if store.isUnlocked {
                    Text("Odemčeno, díky!").font(.headline)
                    Button("Hotovo") { dismiss() }
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
                                Text("Odemknout za \(product.displayPrice)")
                            } else {
                                Text("Načítám…")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.product == nil || store.isPurchasing)

                    Button("Obnovit nákup") {
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
                    Button("Zavřít") { dismiss() }
                }
            }
            .task {
                if store.product == nil { await store.loadProduct() }
            }
        }
    }
}
