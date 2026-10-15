import Foundation
import SwiftData

// Frozen copies of the exact 1.0 models. Never edit this migration fixture.
enum OriginalFolio {

    @Model final class Notebook {
        var id: UUID = UUID()
        var title: String = "Untitled book"
        var colorName: String = "sage"
        var symbol: String = "book.closed"
        var coverStyle: String = "linen"
        var createdAt: Date = Date()
        @Relationship(deleteRule: .cascade, inverse: \NotePage.book)
        var pages: [NotePage]? = []
        @Relationship(deleteRule: .cascade, inverse: \BookSection.book)
        var sections: [BookSection]? = []

        init(title: String, colorName: String = "sage", symbol: String = "book.closed", coverStyle: String = "linen") {
            self.title = title
            self.colorName = colorName
            self.symbol = symbol
            self.coverStyle = coverStyle
        }
        var orderedPages: [NotePage] { (pages ?? []).filter { !$0.isDeleted }.sorted { $0.rank == $1.rank ? $0.id.uuidString < $1.id.uuidString : $0.rank < $1.rank } }
        var entries: [BookEntry] {
            ((pages ?? []).filter { !$0.isDeleted }.map(BookEntry.page) + (sections ?? []).filter { !$0.isDeleted }.map(BookEntry.section))
                .sorted { $0.rank == $1.rank ? $0.id < $1.id : $0.rank < $1.rank }
        }
        var nextRank: Double { (entries.map(\.rank).max() ?? -1) + 1 }
        func applyOrder(_ entries: [BookEntry]) {
            var sectionID: UUID?
            for (index, entry) in entries.enumerated() {
                switch entry {
                case .section(let section):
                    section.rank = Double(index)
                    sectionID = section.id
                case .page(let page):
                    page.rank = Double(index)
                    page.sectionID = sectionID
                }
            }
        }
    }

    @Model final class BookSection {
        var id: UUID = UUID()
        var title: String = "New section"
        var rank: Double = 0
        var book: Notebook?
        init(title: String, rank: Double, book: Notebook) {
            self.title = title
            self.rank = rank
            self.book = book
        }
    }

    enum BookEntry: Identifiable {
        case page(NotePage)
        case section(BookSection)
        var id: String {
            switch self {
            case .page(let page): "page:" + page.id.uuidString
            case .section(let section): "section:" + section.id.uuidString
            }
        }
        var rank: Double {
            switch self {
            case .page(let page): page.rank
            case .section(let section): section.rank
            }
        }
    }

    @Model final class NotePage {
        var id: UUID = UUID()
        var title: String = "Untitled note"
        var text: String = ""
        var createdAt: Date = Date()
        var detectedDate: Date?
        var lastViewedAt: Date?
        var rank: Double = 0
        var sectionID: UUID?
        var tags: [String] = []
        var isFavourite: Bool = false
        var rotation: Int = 0
        var recognitionState: String = "pending"
        var recognitionConfidence: Double = 0
        var suggestedSection: String = ""
        @Attribute(.externalStorage) var imageData: Data = Data()
        @Attribute(.externalStorage) var thumbnailData: Data = Data()
        @Attribute(.externalStorage) var drawingData: Data = Data()
        var book: Notebook?

        init(imageData: Data, thumbnailData: Data, rank: Double, book: Notebook) {
            self.imageData = imageData
            self.thumbnailData = thumbnailData
            self.rank = rank
            self.book = book
        }
        func copy(to destination: Notebook) -> NotePage {
            let page = NotePage(imageData: imageData, thumbnailData: thumbnailData, rank: destination.nextRank, book: destination)
            page.title = title + " copy"
            page.text = text
            page.rotation = rotation
            page.tags = tags
            page.drawingData = drawingData
            page.detectedDate = detectedDate
            page.recognitionState = recognitionState
            page.recognitionConfidence = recognitionConfidence
            page.suggestedSection = suggestedSection
            page.sectionID = (destination.sections ?? []).filter { !$0.isDeleted && $0.rank < page.rank }
                .max(by: { $0.rank < $1.rank })?.id
            return page
        }
    }
}
