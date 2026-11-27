import SwiftUI
import SwiftData

struct PurchaseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// nil = new purchase
    let purchase: Purchase?
    let image: UIImage?
    /// Folder preselected for a new purchase (the folder the list is showing).
    var initialFolder: Folder? = nil
    /// Text already taken from a PDF; when present, OCR is skipped.
    var prefilledText: String? = nil
    /// Shown when more imported receipts wait after this one.
    var queueNote: String? = nil

    @Query(sort: \Folder.createdAt) private var folderQuery: [Folder]

    @State private var productName = ""
    @State private var storeName = ""
    @State private var purchaseDate = Date()
    @State private var priceText = ""
    @State private var warrantyMonths = AppSettings.defaultWarrantyMonths
    @State private var currencyCode = AppSettings.currency
    @State private var notes = ""
    @State private var serialNumber = ""
    @State private var folder: Folder?
    @State private var isReading = false
    @State private var readNote: String?
    @State private var didLoad = false

    private let warrantyOptions = AppSettings.warrantyOptions

    var body: some View {
        NavigationStack {
            Form {
                if let image {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                if isReading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text(L("Čtu účtenku…", "Reading the receipt…"))
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .glassEffect(.regular, in: .capsule)
                                    .padding(10)
                                    .transition(.opacity)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        if let readNote, !isReading {
                            Label(readNote, systemImage: "wand.and.sparkles")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let queueNote {
                            Label(queueNote, systemImage: "tray.full")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .animation(.snappy, value: isReading)
                }

                Section(L("Nákup", "Purchase")) {
                    TextField(L("Co jsi koupil? (např. iPhone 16)", "What did you buy? (e.g. iPhone 16)"), text: $productName)
                        .font(.headline)
                    TextField(L("Obchod", "Store"), text: $storeName)
                    DatePicker(L("Datum nákupu", "Purchase date"), selection: $purchaseDate, in: ...Date(), displayedComponents: .date)
                    HStack {
                        TextField(L("Cena", "Price"), text: $priceText)
                            .keyboardType(.decimalPad)
                        Text(AppSettings.symbol(for: currencyCode)).foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        CurrencyPicker(selection: $currencyCode)
                    } label: {
                        LabeledContent(L("Měna", "Currency"), value: AppSettings.name(for: currencyCode))
                    }
                    TextField(L("Sériové číslo / IMEI", "Serial number / IMEI"), text: $serialNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                }

                Section {
                    Picker(L("Délka záruky", "Warranty length"), selection: $warrantyMonths) {
                        ForEach(pickerOptions, id: \.self) { months in
                            Text(AppFormat.warrantyLength(months: months)).tag(months)
                        }
                    }
                    LabeledContent {
                        Text(AppFormat.date(endDate))
                            .fontWeight(.semibold)
                            .foregroundStyle(endDate < Date() ? Color.secondary : Theme.brand)
                    } label: {
                        Label(L("Konec záruky", "Warranty ends"), systemImage: "calendar.badge.checkmark")
                    }
                } header: {
                    Text(L("Záruka", "Warranty"))
                } footer: {
                    Text(warrantyFooter)
                }

                if !folders.isEmpty {
                    Section(L("Složka", "Folder")) {
                        Picker(L("Složka", "Folder"), selection: $folder) {
                            Text(L("Bez složky", "No folder")).tag(Folder?.none)
                            ForEach(folders) { folder in
                                Text(folder.name).tag(Optional(folder))
                            }
                        }
                    }
                }

                Section(L("Poznámka", "Note")) {
                    TextField(L("Příslušenství, kde je krabice…", "Accessories, where the box is…"), text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(purchase == nil ? L("Nová účtenka", "New receipt") : L("Upravit", "Edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Zrušit", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Uložit", "Save")) { save() }
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

    private var folders: [Folder] {
        folderQuery.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var warrantyFooter: String {
        let legal = L("V EU platí na nové zboží zákonná záruka 24 měsíců.", "In the EU, new goods have a 24-month legal warranty.")
        guard AppSettings.remindersOn else { return legal }
        let days = AppFormat.days(AppSettings.reminderDays)
        return legal + " " + L("Připomenu se \(days) před koncem.", "I'll remind you \(days) before it ends.")
    }

    private var pickerOptions: [Int] {
        warrantyOptions.contains(warrantyMonths) ? warrantyOptions : (warrantyOptions + [warrantyMonths]).sorted()
    }

    private var endDate: Date {
        Calendar.current.date(byAdding: .month, value: warrantyMonths, to: purchaseDate) ?? purchaseDate
    }

    private func loadExisting() {
        guard let purchase else {
            folder = initialFolder
            return
        }
        folder = purchase.folder
        productName = purchase.productName
        storeName = purchase.storeName
        purchaseDate = purchase.purchaseDate
        priceText = purchase.price.map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? ""
        warrantyMonths = purchase.warrantyMonths
        currencyCode = purchase.currencyCode
        notes = purchase.notes
        serialNumber = purchase.serialNumber
    }

    private func read(_ image: UIImage) async {
        isReading = true
        defer { isReading = false }
        let text: String
        if let prefilledText, !prefilledText.isEmpty {
            text = prefilledText
        } else {
            text = (try? await OCRService.recognizeText(in: image)) ?? ""
        }
        guard !text.isEmpty else {
            readNote = L("Text se nepodařilo přečíst, vyplň údaje ručně.", "Couldn't read the text, please fill in the details.")
            return
        }
        let draft = await ReceiptParser.parse(text)
        if productName.isEmpty { productName = draft.productName }
        if storeName.isEmpty { storeName = draft.storeName }
        if let date = draft.purchaseDate { purchaseDate = date }
        if serialNumber.isEmpty, let serial = draft.serialNumber { serialNumber = serial }
        if priceText.isEmpty, let price = draft.price {
            priceText = String(format: "%.2f", price).replacingOccurrences(of: ".", with: ",")
        }
        if let months = draft.warrantyMonths { warrantyMonths = months }
        var suggestedFolder: String?
        if folder == nil, !folders.isEmpty {
            suggestedFolder = await FolderSuggester.suggest(product: productName, store: storeName,
                                                            folders: folders.map(\.name))
            if let suggestedFolder, folder == nil {
                folder = folders.first { $0.name == suggestedFolder }
            }
        }
        readNote = draft.usedAI
            ? L("Vyplněno pomocí AI v telefonu. Zkontroluj prosím údaje.", "Filled in by on-device AI. Please check the details.")
            : L("Vyplněno automaticky. Zkontroluj prosím údaje.", "Filled in automatically. Please check the details.")
        if draft.extendedWarranty, let months = draft.warrantyMonths {
            let length = AppFormat.warrantyLength(months: months)
            readNote = (readNote ?? "") + " " + L("Na účtence je prodloužená záruka, nastavil jsem \(length).",
                                                  "The receipt shows an extended warranty, so it's set to \(length).")
        }
        if let suggestedFolder {
            readNote = (readNote ?? "") + " " + L("Složku „\(suggestedFolder)“ jsem navrhl podle produktu.",
                                                  "Suggested the “\(suggestedFolder)” folder from the product.")
        }
    }

    private var parsedPrice: Double? {
        let cleaned = priceText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private var cleanSerial: String {
        serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
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
            target.currencyCode = currencyCode
            target.notes = notes
            target.serialNumber = cleanSerial
            target.folder = folder
        } else {
            target = Purchase(
                productName: name,
                storeName: storeName,
                purchaseDate: purchaseDate,
                price: parsedPrice,
                warrantyMonths: warrantyMonths,
                notes: notes,
                receiptImageData: image?.jpegData(compressionQuality: 0.7),
                folder: folder
            )
            target.currencyCode = currencyCode
            target.serialNumber = cleanSerial
            modelContext.insert(target)
        }
        try? modelContext.save()
        NotificationService.schedule(for: target)
        dismiss()
    }
}
