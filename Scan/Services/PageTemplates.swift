import Foundation
@preconcurrency import UIKit

actor PageTemplates {
    static let shared = PageTemplates()
    static let styles = ["Blank", "Lined", "Squared", "Dotted", "Graph"]
    func make(_ style: String) async throws -> PreparedPage {
        let size = CGSize(width: 1600, height: 2264)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            let step: CGFloat = style == "Graph" ? 24 : 48
            let left: CGFloat = 96, top: CGFloat = 120
            cg.setStrokeColor(UIColor(red: 0.62, green: 0.7, blue: 0.73, alpha: 0.4).cgColor)
            cg.setLineWidth(1)
            if ["Lined", "Squared", "Graph"].contains(style) {
                var y = top
                while y < size.height - 90 {
                    cg.move(to: CGPoint(x: left, y: y)); cg.addLine(to: CGPoint(x: size.width - left, y: y)); y += step
                }
                if style != "Lined" {
                    var x = left
                    while x <= size.width - left {
                        cg.move(to: CGPoint(x: x, y: top)); cg.addLine(to: CGPoint(x: x, y: size.height - 90)); x += step
                    }
                }
                cg.strokePath()
            }
            if style == "Graph" {
                cg.setLineWidth(2)
                var x = left
                while x <= size.width - left {
                    cg.move(to: CGPoint(x: x, y: top)); cg.addLine(to: CGPoint(x: x, y: size.height - 90)); x += step * 5
                }
                var y = top
                while y < size.height - 90 {
                    cg.move(to: CGPoint(x: left, y: y)); cg.addLine(to: CGPoint(x: size.width - left, y: y)); y += step * 5
                }
                cg.strokePath()
            }
            if style == "Dotted" {
                cg.setFillColor(UIColor.systemGray3.cgColor)
                var y = top
                while y < size.height - 90 {
                    var x = left
                    while x < size.width - left { cg.fillEllipse(in: CGRect(x: x, y: y, width: 3, height: 3)); x += step }
                    y += step
                }
            }
            if style == "Lined" {
                cg.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.25).cgColor)
                cg.move(to: CGPoint(x: left + 80, y: 70)); cg.addLine(to: CGPoint(x: left + 80, y: size.height - 70)); cg.strokePath()
            }
        }
        guard let data = image.jpegData(compressionQuality: 0.94) else { throw DocumentError.unreadable }
        return try await DocumentProcessor.shared.prepare(data)
    }
}
