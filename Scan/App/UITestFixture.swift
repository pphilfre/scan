import Foundation
#if DEBUG
import SwiftData
import UIKit

/// UI automation always uses an isolated, disposable store.
@MainActor enum UITestFixture {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }
    static func seed(_ context: ModelContext) throws {
        let book = Notebook(title: "Physics")
        context.insert(book)
        let section = BookSection(title: "Mechanics", rank: 0, book: book)
        context.insert(section)
        let bytes = imageData()
        for index in 1...3 {
            let page = NotePage(imageData: bytes, thumbnailData: bytes, rank: Double(index), book: book)
            page.title = "Lecture \(index)"; page.text = "Energy is conserved. Lecture \(index)."
            page.recognitionState = "complete"; page.sectionID = section.id
            context.insert(page)
            context.insert(PageRevision(page: page, reason: "Original scan"))
        }
        try LibraryPersistence.save(context)
    }
    static func imageData() -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1300), format: format).image { renderer in
            UIColor.white.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 900, height: 1300))
            ("Physics lecture\nEnergy is conserved" as NSString).draw(at: CGPoint(x: 70, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black])
        }.pngData()!
    }
    static func importURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Imported lecture.png")
        try imageData().write(to: url)
        return url
    }
}
#endif
