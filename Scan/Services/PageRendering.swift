import Foundation
import SwiftData
@preconcurrency import UIKit
import PencilKit
import ImageIO
import CoreImage
import CoreImage.CIFilterBuiltins

struct PageSnapshot: Sendable {
    let image: Data
    let drawing: Data
    var photos: [PagePhoto]
    var rotation: Int
    var adjustments: ImageAdjustments
    let key: String
    init(_ page: NotePage) {
        image = page.imageData; drawing = page.drawingData; photos = page.photoLayers; rotation = page.rotation
        adjustments = ImageAdjustments(data: page.enhancementData)
        key = page.id.uuidString + ":" + page.visualVersion.uuidString
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
    static func filteredBase(_ data: Data, adjustments: ImageAdjustments, photos: [PagePhoto] = [], maximum: Int = 2800) -> UIImage? {
        guard let source = baseImage(data, maximum: maximum) else { return nil }
        let composed: UIImage
        if !photos.isEmpty {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            composed = UIGraphicsImageRenderer(size: source.size, format: format).image { _ in
                source.draw(in: CGRect(origin: .zero, size: source.size))
                for photo in photos {
                    guard let inserted = baseImage(photo.data, maximum: maximum) else { continue }
                    let rect = photo.rect.clamped
                    let box = CGRect(x: rect.x * source.size.width, y: rect.y * source.size.height,
                                     width: rect.width * source.size.width, height: rect.height * source.size.height)
                    let fit = min(box.width / inserted.size.width, box.height / inserted.size.height)
                    let size = CGSize(width: inserted.size.width * fit, height: inserted.size.height * fit)
                    inserted.draw(in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height))
                }
            }
        } else { composed = source }
        guard let cg = composed.cgImage else { return nil }
        var output = CIImage(cgImage: cg)
        let controls = CIFilter.colorControls()
        controls.inputImage = output
        controls.brightness = Float(adjustments.brightness)
        controls.contrast = Float(adjustments.contrast)
        controls.saturation = adjustments.filter == "grayscale" || adjustments.filter == "mono" ? 0 : 1
        output = controls.outputImage ?? output
        if adjustments.filter == "mono" { output = output.applyingFilter("CIPhotoEffectNoir") }
        if adjustments.filter == "sepia" { output = output.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.55]) }
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let result = context.createCGImage(output, from: output.extent) else { return source }
        return UIImage(cgImage: result)
    }
    static func image(_ page: PageSnapshot, maximum: Int = 2800) -> UIImage? {
        guard let base = filteredBase(page.image, adjustments: page.adjustments, photos: page.photos, maximum: maximum) else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let full = UIGraphicsImageRenderer(size: base.size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: base.size))
            context.cgContext.translateBy(x: base.size.width / 2, y: base.size.height / 2)
            context.cgContext.rotate(by: CGFloat(page.adjustments.straighten) * .pi / 180)
            let rect = CGRect(x: -base.size.width / 2, y: -base.size.height / 2, width: base.size.width, height: base.size.height)
            base.draw(in: rect)
            if let drawing = try? PKDrawing(data: page.drawing), !drawing.strokes.isEmpty {
                let canvas = CGRect(x: 0, y: 0, width: 1000, height: 1000 * base.size.height / base.size.width)
                drawing.image(from: canvas, scale: base.size.width / 1000).draw(in: rect)
            }
        }
        let crop = page.adjustments.crop.clamped
        let rect = CGRect(x: crop.x * full.size.width, y: crop.y * full.size.height,
                          width: crop.width * full.size.width, height: crop.height * full.size.height).integral
        guard let cropped = full.cgImage?.cropping(to: rect) else { return full }
        let image = UIImage(cgImage: cropped)
        let turns = (page.rotation % 4 + 4) % 4
        guard turns != 0 else { return image }
        let size = turns % 2 == 1 ? CGSize(width: image.size.height, height: image.size.width) : image.size
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: CGFloat(turns) * .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }
}

actor PageImageRenderer {
    static let shared = PageImageRenderer()
    private let cache = NSCache<NSString, NSData>()
    init() { cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 12 }
    func render(_ page: PageSnapshot, maximum: Int = 2400) -> Data? {
        let key = "\(page.key):\(maximum)" as NSString
        if let data = cache.object(forKey: key) { return data as Data }
        let result = autoreleasepool { PageRendering.image(page, maximum: maximum)?.jpegData(compressionQuality: maximum < 800 ? 0.8 : 0.93) }
        if let result { cache.setObject(result as NSData, forKey: key, cost: result.count) }
        return result
    }
    func preview(_ page: PageSnapshot) -> Data? {
        autoreleasepool { PageRendering.image(page, maximum: 1100)?.jpegData(compressionQuality: 0.85) }
    }
    func annotationBase(_ page: PageSnapshot) -> Data? {
        autoreleasepool { PageRendering.filteredBase(page.image, adjustments: page.adjustments, photos: page.photos)?.jpegData(compressionQuality: 0.94) }
    }
    func clear() { cache.removeAllObjects() }
}

@MainActor final class ThumbnailMemory {
    static let shared = ThumbnailMemory()
    private let cache = NSCache<NSString, UIImage>()
    private init() { cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 100 }
    func image(data: Data, key: String) -> UIImage? {
        if let image = cache.object(forKey: key as NSString) { return image }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
    func clear() { cache.removeAllObjects(); Task { await PageImageRenderer.shared.clear() } }
}

actor PDFExporter {
    static let shared = PDFExporter()
    func export(_ pages: [PageSnapshot], title: String) throws -> URL {
        try makePDF(title: title, count: pages.count) { pages[$0] }
    }
    /// Each page uses a short-lived read context. The main context never faults
    /// every original into memory just to build an export request.
    func export(pageIDs: [UUID], container: ModelContainer, title: String) throws -> URL {
        try makePDF(title: title, count: pageIDs.count) { index in
            let context = ModelContext(container)
            let id = pageIDs[index]
            var descriptor = FetchDescriptor<NotePage>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let page = try context.fetch(descriptor).first, page.trashedAt == nil, page.book?.trashedAt == nil else { throw DocumentError.unreadable }
            return PageSnapshot(page)
        }
    }
    private func makePDF(title: String, count: Int, page: (Int) throws -> PageSnapshot) throws -> URL {
        guard count > 0 else { throw DocumentError.emptyPDF }
        let name = String(title.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }.map(String.init).joined().prefix(60))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name.isEmpty ? "Notes" : name)-\(UUID().uuidString.prefix(6)).pdf")
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Folio"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842), format: format)
        var renderingError: Error?
        try renderer.writePDF(to: url) { context in
            for index in 0..<count where renderingError == nil {
                autoreleasepool {
                    do {
                        guard let image = PageRendering.image(try page(index)) else { throw DocumentError.unreadable }
                        let rect = CGRect(x: 0, y: 0, width: 595, height: 595 * image.size.height / image.size.width)
                        context.beginPage(withBounds: rect, pageInfo: [:]); image.draw(in: rect)
                    } catch { renderingError = error }
                }
            }
        }
        if let renderingError { try? FileManager.default.removeItem(at: url); throw renderingError }
        return url
    }
}
