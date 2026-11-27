import UIKit
import Vision

enum OCRService {
    /// Reads all text from a receipt image on device.
    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = OCRService.languages(for: request)
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])
            let observations = request.results ?? []
            return observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }

    /// The app language first, then English, German and Czech, limited to what Vision can read
    /// on this iOS version, since an unsupported code can make the request fail.
    private static func languages(for request: VNRecognizeTextRequest) -> [String] {
        let supported = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
        var wanted = [L10n.language.rawValue]
        for code in ["en", "de", "cs"] where !wanted.contains(code) { wanted.append(code) }
        let picked = wanted.compactMap { code in
            supported.first { $0.lowercased().hasPrefix(code + "-") || $0.lowercased() == code }
        }
        return picked.isEmpty ? ["en-US"] : picked
    }

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
