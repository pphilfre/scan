import Foundation
@preconcurrency import UIKit
import PencilKit
import ImageIO

struct PageSnapshot: Sendable {
    let image: Data
    let drawing: Data
    let rotation: Int
    init(_ page: NotePage) {
        image = page.imageData
        drawing = page.drawingData
        rotation = page.rotation
    }
}

enum PageRendering {
    static func baseImage(_ data: Data, maximum: Int = 2800) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximum
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
    static func image(_ page: PageSnapshot) -> UIImage? {
        guard let image = baseImage(page.image) else { return nil }
        let turns = (page.rotation % 4 + 4) % 4
        let rotated = turns % 2 == 1
        let size = rotated ? CGSize(width: image.size.height, height: image.size.width) : image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: CGFloat(turns) * .pi / 2)
            let rect = CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height)
            image.draw(in: rect)
            if let drawing = try? PKDrawing(data: page.drawing), !drawing.strokes.isEmpty {
                // Ink coordinates use a fixed 1000-point page width at every resolution.
                let canvas = CGRect(x: 0, y: 0, width: 1000, height: 1000 * image.size.height / image.size.width)
                drawing.image(from: canvas, scale: image.size.width / 1000).draw(in: rect)
            }
        }
    }
}

actor PDFExporter {
    static let shared = PDFExporter()
    func export(_ pages: [PageSnapshot], title: String) throws -> URL {
        let name = String(title.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }.map(String.init).joined().prefix(60))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name.isEmpty ? "Notes" : name)-\(UUID().uuidString.prefix(6)).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842), format: {
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Folio"]
            return format
        }())
        var unreadable = false
        try renderer.writePDF(to: url) { context in
            for page in pages {
                autoreleasepool {
                    guard let image = PageRendering.image(page) else { unreadable = true; return }
                    let size = CGSize(width: 595, height: 595 * image.size.height / image.size.width)
                    let rect = CGRect(origin: .zero, size: size)
                    context.beginPage(withBounds: rect, pageInfo: [:])
                    image.draw(in: rect)
                }
            }
        }
        if unreadable {
            try? FileManager.default.removeItem(at: url)
            throw DocumentError.unreadable
        }
        return url
    }
}
