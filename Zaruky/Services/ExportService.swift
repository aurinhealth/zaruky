import Foundation
import UIKit

/// A plain copy of one receipt, taken on the main actor so the files can be built in the background.
struct ExportItem: Sendable {
    let productName: String
    let storeName: String
    let folderName: String
    let purchaseDate: Date
    let warrantyEndDate: Date
    let warrantyMonths: Int
    let price: Double?
    let currencyCode: String
    let notes: String
    let statusTitle: String
    let imageData: Data?
    let serialNumber: String
    /// Warranty card, product photo… with their kind's name.
    let attachments: [(title: String, data: Data)]

    @MainActor
    init(_ purchase: Purchase) {
        productName = purchase.productName.isEmpty ? L("Bez názvu", "Untitled", "Ohne Namen") : purchase.productName
        storeName = purchase.storeName
        folderName = purchase.folder?.name ?? ""
        purchaseDate = purchase.purchaseDate
        warrantyEndDate = purchase.warrantyEndDate
        warrantyMonths = purchase.warrantyMonths
        price = purchase.price
        currencyCode = purchase.currencyCode
        notes = purchase.notes
        statusTitle = purchase.status.title
        imageData = purchase.receiptImageData
        serialNumber = purchase.serialNumber
        attachments = purchase.sortedAttachments.compactMap { a in a.imageData.map { (title: a.kind.title, data: $0) } }
    }
}

/// Builds the files offered by Settings → Export: a PDF overview with the receipt photos,
/// and a ZIP backup with the PDF, a CSV table (opens in Excel/Numbers) and the original photos.
enum ExportService {
    enum Kind { case pdf, zip }

    static func export(_ items: [ExportItem], as kind: Kind) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            switch kind {
            case .pdf: return try makePDF(items)
            case .zip: return try makeZIP(items)
            }
        }.value
    }

    // MARK: Files

    private static var stamp: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func freshDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var baseName: String { L("Zaruky-", "Warranties-", "Garantien-") + stamp }

    static func makePDF(_ items: [ExportItem]) throws -> URL {
        let url = try freshDirectory().appendingPathComponent(baseName + ".pdf")
        try pdfData(items).write(to: url)
        return url
    }

    static func makeZIP(_ items: [ExportItem]) throws -> URL {
        let fm = FileManager.default
        let work = try freshDirectory()
        let folder = work.appendingPathComponent(baseName, isDirectory: true)
        let photos = folder.appendingPathComponent(L("fotky", "photos", "fotos"), isDirectory: true)
        try fm.createDirectory(at: photos, withIntermediateDirectories: true)

        var photoNames: [String?] = []
        for (index, item) in items.enumerated() {
            guard let data = item.imageData else { photoNames.append(nil); continue }
            let name = String(format: "%03d-", index + 1) + safeFileName(item.productName) + ".jpg"
            try data.write(to: photos.appendingPathComponent(name))
            photoNames.append(name)
        }
        // Extra documents next to the receipt photos: 001-iPhone-16-Zarucni-list-1.jpg
        for (index, item) in items.enumerated() {
            for (number, attachment) in item.attachments.enumerated() {
                let name = String(format: "%03d-", index + 1) + safeFileName(item.productName) + "-"
                    + safeFileName(attachment.title.folding(options: .diacriticInsensitive, locale: nil)) + "-\(number + 1).jpg"
                try attachment.data.write(to: photos.appendingPathComponent(name))
            }
        }
        try csv(items, photoNames: photoNames).write(to: folder.appendingPathComponent(L("uctenky.csv", "receipts.csv", "belege.csv")))
        try pdfData(items).write(to: folder.appendingPathComponent(L("prehled.pdf", "overview.pdf", "uebersicht.pdf")))

        // The system zips a folder when it is read "for uploading"; copy the zip out before it's cleaned up.
        let destination = work.appendingPathComponent(baseName + ".zip")
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinatorError) { zipURL in
            do { try fm.copyItem(at: zipURL, to: destination) } catch { copyError = error }
        }
        if let error = coordinatorError ?? copyError { throw error }
        return destination
    }

    private static func safeFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = String(name.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
        return String((cleaned.isEmpty ? "uctenka" : cleaned).prefix(40))
    }

    // MARK: CSV

    /// Semicolon separated with a BOM, so Czech Excel opens it with the right columns and diacritics.
    static func csv(_ items: [ExportItem], photoNames: [String?]) -> Data {
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"

        func field(_ s: String) -> String {
            let needsQuotes = s.contains(";") || s.contains("\"") || s.contains("\n")
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return needsQuotes ? "\"\(escaped)\"" : escaped
        }
        func number(_ v: Double?) -> String {
            guard let v else { return "" }
            let text = String(format: "%.2f", v)
            return L10n.locale.decimalSeparator == "," ? text.replacingOccurrences(of: ".", with: ",") : text
        }

        let header = L("Produkt;Obchod;Složka;Datum nákupu;Záruka (měsíce);Konec záruky;Stav;Cena;Měna;Sériové číslo;Poznámka;Fotka", "Product;Store;Folder;Purchase date;Warranty (months);Warranty ends;Status;Price;Currency;Serial number;Note;Photo", "Produkt;Geschäft;Ordner;Kaufdatum;Garantie (Monate);Garantie endet;Status;Preis;Währung;Seriennummer;Notiz;Foto")
        var lines = [header]
        for (index, item) in items.enumerated() {
            let photo = index < photoNames.count ? photoNames[index].map { L("fotky/", "photos/", "fotos/") + $0 } ?? "" : ""
            lines.append([
                field(item.productName), field(item.storeName), field(item.folderName),
                iso.string(from: item.purchaseDate), String(item.warrantyMonths), iso.string(from: item.warrantyEndDate),
                field(item.statusTitle), number(item.price), item.currencyCode, field(item.serialNumber), field(item.notes), field(photo),
            ].joined(separator: ";"))
        }
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    // MARK: PDF

    private static let page = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4 in points
    private static let margin: CGFloat = 40
    private static let brand = UIColor(red: 0.03, green: 0.48, blue: 0.35, alpha: 1)

    /// First pages: a table of every receipt. Then one page per receipt photo.
    static func pdfData(_ items: [ExportItem]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let width = page.width - margin * 2

        let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: UIColor.black]
        let subtitle: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray]
        let head: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: UIColor.gray]
        let cell: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.black]
        let cellBold: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.black]
        let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray]

        // Column x offsets and widths: product+store, bought, warranty until, status, price.
        let columns: [(String, CGFloat)] = [
            (L("PRODUKT", "PRODUCT", "PRODUKT"), 0.36), (L("KOUPENO", "BOUGHT", "GEKAUFT"), 0.15), (L("ZÁRUKA DO", "WARRANTY UNTIL", "GARANTIE BIS"), 0.17),
            (L("STAV", "STATUS", "STATUS"), 0.15), (L("CENA", "PRICE", "PREIS"), 0.17),
        ]
        func columnRects(y: CGFloat, height: CGFloat) -> [CGRect] {
            var x = margin
            return columns.map { _, share in
                defer { x += width * share }
                return CGRect(x: x, y: y, width: width * share - 6, height: height)
            }
        }

        return renderer.pdfData { context in
            var y: CGFloat = 0

            func newPage(first: Bool) {
                context.beginPage()
                y = margin
                if first {
                    NSAttributedString(string: L("Záruky – přehled účtenek", "Warranties – receipt overview", "Garantien – Belegübersicht"), attributes: title)
                        .draw(at: CGPoint(x: margin, y: y))
                    y += 34
                    NSAttributedString(string: L("Vytvořeno \(AppFormat.date(Date())) · \(AppFormat.receipts(items.count))", "Created \(AppFormat.date(Date())) · \(AppFormat.receipts(items.count))", "Erstellt am \(AppFormat.date(Date())) · \(AppFormat.receipts(items.count))"),
                                       attributes: subtitle)
                        .draw(at: CGPoint(x: margin, y: y))
                    y += 30
                }
                for (rect, column) in zip(columnRects(y: y, height: 14), columns) {
                    NSAttributedString(string: column.0, attributes: head).draw(in: rect)
                }
                y += 18
                strokeLine(context.cgContext, y: y)
                y += 6
            }

            newPage(first: true)
            for item in items {
                let rowHeight: CGFloat = item.storeName.isEmpty && item.folderName.isEmpty ? 22 : 34
                if y + rowHeight > page.height - margin { newPage(first: false) }
                let rects = columnRects(y: y, height: rowHeight)
                NSAttributedString(string: item.productName, attributes: cellBold).draw(in: rects[0].insetBy(dx: 0, dy: 0))
                let sub = [item.storeName, item.folderName].filter { !$0.isEmpty }.joined(separator: " · ")
                if !sub.isEmpty {
                    NSAttributedString(string: sub, attributes: small).draw(in: rects[0].offsetBy(dx: 0, dy: 14))
                }
                NSAttributedString(string: shortDate(item.purchaseDate), attributes: cell).draw(in: rects[1])
                NSAttributedString(string: shortDate(item.warrantyEndDate), attributes: cell).draw(in: rects[2])
                NSAttributedString(string: item.statusTitle, attributes: cell).draw(in: rects[3])
                NSAttributedString(string: AppFormat.price(item.price, currency: item.currencyCode), attributes: cell).draw(in: rects[4])
                y += rowHeight
                strokeLine(context.cgContext, y: y - 4, color: UIColor(white: 0.9, alpha: 1))
                y += 4
            }

            // One page per photo, with the details on top, ready to print for a claim.
            for item in items {
                var pages: [(title: String?, data: Data)] = []
                if let data = item.imageData { pages.append((title: nil, data: data)) }
                pages += item.attachments.map { (title: Optional($0.title), data: $0.data) }
                for pageImage in pages {
                    guard let image = UIImage(data: pageImage.data) else { continue }
                    context.beginPage()
                    var top = margin
                    let heading = pageImage.title.map { item.productName + " – " + $0 } ?? item.productName
                    NSAttributedString(string: heading, attributes: title).draw(in: CGRect(x: margin, y: top, width: width, height: 32))
                    top += 34
                    let details = [item.storeName,
                                   L("koupeno \(AppFormat.date(item.purchaseDate))", "bought \(AppFormat.date(item.purchaseDate))", "gekauft \(AppFormat.date(item.purchaseDate))"),
                                   L("záruka do \(AppFormat.date(item.warrantyEndDate))", "warranty until \(AppFormat.date(item.warrantyEndDate))", "Garantie bis \(AppFormat.date(item.warrantyEndDate))"),
                                   AppFormat.price(item.price, currency: item.currencyCode),
                                   item.serialNumber.isEmpty ? "" : L("S/N \(item.serialNumber)", "S/N \(item.serialNumber)", "S/N \(item.serialNumber)")]
                        .filter { !$0.isEmpty && $0 != "—" }
                        .joined(separator: " · ")
                    NSAttributedString(string: details, attributes: subtitle).draw(in: CGRect(x: margin, y: top, width: width, height: 30))
                    top += 30
                    let box = CGRect(x: margin, y: top, width: width, height: page.height - margin - top)
                    image.draw(in: aspectFit(image.size, in: box))
                }
            }
        }
    }

    private static func strokeLine(_ cg: CGContext, y: CGFloat, color: UIColor = brand) {
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(0.6)
        cg.move(to: CGPoint(x: margin, y: y))
        cg.addLine(to: CGPoint(x: page.width - margin, y: y))
        cg.strokePath()
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.defaultDigits).year().locale(L10n.locale))
    }

    private static func aspectFit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: box.midX - w / 2, y: box.minY, width: w, height: h)
    }
}
