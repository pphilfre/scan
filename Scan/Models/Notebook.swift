import Foundation
import SwiftData

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
