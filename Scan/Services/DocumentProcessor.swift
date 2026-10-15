import Foundation
@preconcurrency import UIKit
@preconcurrency import Vision
import PDFKit
import ImageIO

/// Immutable UIKit images are passed to the serial processor and never mutated.
struct ImmutableScanImage: @unchecked Sendable { let image: UIImage }

struct PreparedPage: Sendable {
    let original: Data
    let thumbnail: Data
}
struct Recognition: Sendable {
    let text: String
    let confidence: Double
}

enum DocumentError: LocalizedError {
    case unreadable, lockedPDF, tooManyPages, emptyPDF
    var errorDescription: String? {
        switch self {
        case .unreadable: "This file couldn’t be read as an image or PDF."
        case .lockedPDF: "This PDF is password protected. Unlock it before importing."
        case .tooManyPages: "Import up to 100 pages at a time. Split this PDF into smaller files."
        case .emptyPDF: "This PDF has no pages."
        }
    }
}

/// Serial actor keeps image decoding, PDF rendering and Vision away from the UI thread.
actor DocumentProcessor {
    static let shared = DocumentProcessor()
    func prepareScan(_ scan: ImmutableScanImage) throws -> PreparedPage {
        try autoreleasepool {
            guard let data = scan.image.jpegData(compressionQuality: 0.96) else { throw DocumentError.unreadable }
            return try prepare(data)
        }
    }
    func prepare(_ data: Data) throws -> PreparedPage {
        guard let image = Self.downsample(data, maxSize: 500),
              let thumbnail = image.jpegData(compressionQuality: 0.8) else { throw DocumentError.unreadable }
        return PreparedPage(original: data, thumbnail: thumbnail)
    }
    func pdfPageCount(at url: URL) throws -> Int {
        guard let document = PDFDocument(url: url) else { throw DocumentError.unreadable }
        guard !document.isLocked else { throw DocumentError.lockedPDF }
        guard document.pageCount > 0 else { throw DocumentError.emptyPDF }
        guard document.pageCount <= 100 else { throw DocumentError.tooManyPages }
        return document.pageCount
    }
    func renderPDFPage(at url: URL, index: Int) throws -> PreparedPage {
        try autoreleasepool {
            guard let document = PDFDocument(url: url), let page = document.page(at: index) else { throw DocumentError.unreadable }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { throw DocumentError.unreadable }
            let scale = min(3, 2800 / max(bounds.width, bounds.height))
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.scaleBy(x: scale, y: scale)
                ctx.cgContext.translateBy(x: -bounds.minX, y: bounds.maxY)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            guard let data = image.jpegData(compressionQuality: 0.94) else { throw DocumentError.unreadable }
            return try prepare(data)
        }
    }
    func recognise(_ data: Data, rotation: Int, vocabulary: [String]) throws -> Recognition {
        try autoreleasepool {
            guard let image = Self.downsample(data, maxSize: 3200), let cgImage = image.cgImage else { throw DocumentError.unreadable }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.customWords = vocabulary
            request.minimumTextHeight = 0.003
            let orientation: CGImagePropertyOrientation = switch (rotation % 4 + 4) % 4 {
            case 1: .right
            case 2: .down
            case 3: .left
            default: .up
            }
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
            return Recognition(text: candidates.map(\.string).joined(separator: "\n"),
                confidence: candidates.isEmpty ? 0 : Double(candidates.map(\.confidence).reduce(0, +)) / Double(candidates.count))
        }
    }
    private static func downsample(_ data: Data, maxSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
