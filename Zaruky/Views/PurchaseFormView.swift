import SwiftUI
import SwiftData

struct PurchaseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// nil = new purchase
    let purchase: Purchase?
    let image: UIImage?

    @State private var productName = ""
    @State private var storeName = ""
    @State private var purchaseDate = Date()
    @State private var priceText = ""
    @State private var warrantyMonths = 24
    @State private var notes = ""
    @State private var isReading = false
    @State private var readNote: String?
    @State private var didLoad = false

    private let warrantyOptions = [6, 12, 24, 36, 48, 60]

    var body: some View {
        NavigationStack {
            Form {
                if let image {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                        if isReading {
                            HStack {
                                ProgressView()
                                Text("Čtu účtenku…").foregroundStyle(.secondary)
                            }
                        } else if let readNote {
                            Text(readNote).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Nákup") {
                    TextField("Produkt", text: $productName)
                    TextField("Obchod", text: $storeName)
                    DatePicker("Datum nákupu", selection: $purchaseDate, in: ...Date(), displayedComponents: .date)
                    TextField("Cena (Kč)", text: $priceText)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Picker("Délka záruky", selection: $warrantyMonths) {
                        ForEach(pickerOptions, id: \.self) { months in
                            Text(CzechFormat.warrantyLength(months: months)).tag(months)
                        }
                    }
                    LabeledContent("Konec záruky", value: CzechFormat.date(endDate))
                } header: {
                    Text("Záruka")
                } footer: {
                    Text("V EU platí na nové zboží zákonná záruka 24 měsíců. Připomenu se 30 dní před koncem.")
                }

                Section("Poznámka") {
                    TextField("Sériové číslo, příslušenství…", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(purchase == nil ? "Nová účtenka" : "Upravit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit") { save() }
                        .disabled(productName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                loadExisting()
                if purchase == nil, let image { await read(image) }
            }
        }
    }

    private var pickerOptions: [Int] {
        warrantyOptions.contains(warrantyMonths) ? warrantyOptions : (warrantyOptions + [warrantyMonths]).sorted()
    }

    private var endDate: Date {
        Calendar.current.date(byAdding: .month, value: warrantyMonths, to: purchaseDate) ?? purchaseDate
    }

    private func loadExisting() {
        guard let purchase else { return }
        productName = purchase.productName
        storeName = purchase.storeName
        purchaseDate = purchase.purchaseDate
        priceText = purchase.price.map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? ""
        warrantyMonths = purchase.warrantyMonths
        notes = purchase.notes
    }

    private func read(_ image: UIImage) async {
        isReading = true
        defer { isReading = false }
        let text = (try? await OCRService.recognizeText(in: image)) ?? ""
        guard !text.isEmpty else {
            readNote = "Text se nepodařilo přečíst, vyplň údaje ručně."
            return
        }
        let draft = await ReceiptParser.parse(text)
        if productName.isEmpty { productName = draft.productName }
        if storeName.isEmpty { storeName = draft.storeName }
        if let date = draft.purchaseDate { purchaseDate = date }
        if priceText.isEmpty, let price = draft.price {
            priceText = String(format: "%.2f", price).replacingOccurrences(of: ".", with: ",")
        }
        warrantyMonths = draft.warrantyMonths
        readNote = draft.usedAI
            ? "Vyplněno pomocí AI v telefonu. Zkontroluj prosím údaje."
            : "Vyplněno automaticky. Zkontroluj prosím údaje."
    }

    private var parsedPrice: Double? {
        let cleaned = priceText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private func save() {
        let name = productName.trimmingCharacters(in: .whitespaces)
        let target: Purchase
        if let purchase {
            target = purchase
            target.productName = name
            target.storeName = storeName
            target.purchaseDate = purchaseDate
            target.price = parsedPrice
            target.warrantyMonths = warrantyMonths
            target.notes = notes
        } else {
            target = Purchase(
                productName: name,
                storeName: storeName,
                purchaseDate: purchaseDate,
                price: parsedPrice,
                warrantyMonths: warrantyMonths,
                notes: notes,
                receiptImageData: image?.jpegData(compressionQuality: 0.7)
            )
            modelContext.insert(target)
        }
        try? modelContext.save()
        NotificationService.schedule(for: target)
        dismiss()
    }
}
