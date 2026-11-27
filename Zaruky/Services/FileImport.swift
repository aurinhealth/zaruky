import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// A receipt picked from the Files app or opened in Záruky from another app.
struct ImportedReceipt {
    let image: UIImage
    /// Text already inside the file (digital PDF invoices), so OCR isn't needed.
    let text: String?
}

/// Turns a PDF or image file into a receipt picture (and its text, for PDFs that have it).
enum FileImport {
    static let contentTypes: [UTType] = [.pdf, .image]

    /// Pages of a PDF stacked into one picture. E-shop invoices are usually 1–2 pages.
    static let maxPages = 3

    static func load(_ url: URL) -> ImportedReceipt? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if type?.conforms(to: .pdf) == true, let pdf = PDFDocument(url: url) {
            return fromPDF(pdf)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let pdf = PDFDocument(data: data), pdf.pageCount > 0 {
            return fromPDF(pdf)
        }
        return UIImage(data: data).map { ImportedReceipt(image: $0, text: nil) }
    }

    private static func fromPDF(_ pdf: PDFDocument) -> ImportedReceipt? {
        let count = min(pdf.pageCount, maxPages)
        let pages = (0..<count).compactMap { pdf.page(at: $0) }
        guard !pages.isEmpty else { return nil }

        let text = pages.compactMap(\.string).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Render at ~2x of A4 width so small print stays readable, then stack vertically.
        let targetWidth: CGFloat = 1240
        let sizes = pages.map { page -> CGSize in
            let box = page.bounds(for: .mediaBox).size
            let rotated = page.rotation % 180 != 0
            let w = rotated ? box.height : box.width
            let h = rotated ? box.width : box.height
            let scale = w > 0 ? targetWidth / w : 1
            return CGSize(width: targetWidth, height: h * scale)
        }
        let total = CGSize(width: targetWidth, height: sizes.reduce(0) { $0 + $1.height })
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: total, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: total))
            var y: CGFloat = 0
            for (page, size) in zip(pages, sizes) {
                let thumb = page.thumbnail(of: size, for: .mediaBox)
                thumb.draw(in: CGRect(x: 0, y: y, width: size.width, height: size.height))
                y += size.height
            }
        }
        return ImportedReceipt(image: image, text: text.count > 20 ? text : nil)
    }
}
