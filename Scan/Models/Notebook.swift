import Foundation
import SwiftData

@Model final class Notebook {
    var id: UUID = UUID()
    var title: String = "Untitled book"
    var colorName: String = "sage"
    var symbol: String = "book.closed"
    var coverStyle: String = "linen"
    var createdAt: Date = Date()
    // Optional persisted additions can migrate old rows without a SQL default.
    @Attribute(originalName: "modifiedAt") var storedModifiedAt: Date?
    var modifiedAt: Date {
        get { storedModifiedAt ?? createdAt }
        set { storedModifiedAt = newValue }
    }
    // Additive fields keep the original entity, attributes and relationships intact.
    var gradientColorName: String = "blue"
    var spineLabel: String = ""
    var textureStrength: Double = 0.16
    var isLocked: Bool = false
    var trashedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \NotePage.book)
    var pages: [NotePage]? = []
    @Relationship(deleteRule: .cascade, inverse: \BookSection.book)
    var sections: [BookSection]? = []

    init(title: String, colorName: String = "sage", symbol: String = "book.closed", coverStyle: String = "linen") {
        self.title = title; self.colorName = colorName; self.symbol = symbol; self.coverStyle = coverStyle
    }
    var orderedPages: [NotePage] {
        (pages ?? []).filter { !$0.isDeleted && $0.trashedAt == nil }
            .sorted { $0.rank == $1.rank ? $0.id.uuidString < $1.id.uuidString : $0.rank < $1.rank }
    }
    var activeSections: [BookSection] {
        (sections ?? []).filter { !$0.isDeleted && $0.trashedAt == nil }
            .sorted { $0.rank == $1.rank ? $0.id.uuidString < $1.id.uuidString : $0.rank < $1.rank }
    }
    var entries: [BookEntry] {
        (orderedPages.map(BookEntry.page) + activeSections.map(BookEntry.section))
            .sorted { $0.rank == $1.rank ? $0.id < $1.id : $0.rank < $1.rank }
    }
    var nextRank: Double { (entries.map(\.rank).max() ?? -1) + 1 }
    func applyOrder(_ entries: [BookEntry]) {
        var sectionID: UUID?
        for (index, entry) in entries.enumerated() {
            switch entry {
            case .section(let section):
                if section.rank != Double(index) { section.modifiedAt = .now }
                section.rank = Double(index); sectionID = section.id
            case .page(let page):
                if page.rank != Double(index) || page.sectionID != sectionID { page.modifiedAt = .now }
                page.rank = Double(index); page.sectionID = sectionID
            }
        }
        modifiedAt = .now
    }
    func descendantIDs(of sectionID: UUID) -> Set<UUID> {
        var result: Set<UUID> = [sectionID]
        var changed = true
        while changed {
            changed = false
            for section in activeSections where section.parentID.map(result.contains) == true {
                if result.insert(section.id).inserted { changed = true }
            }
        }
        return result
    }
    func pages(in section: BookSection) -> [NotePage] {
        let ids = descendantIDs(of: section.id)
        return orderedPages.filter { $0.sectionID.map(ids.contains) == true }
    }
    func depth(of section: BookSection) -> Int {
        var seen: Set<UUID> = [section.id]
        var parent = section.parentID
        var depth = 0
        while let id = parent, seen.insert(id).inserted,
              let item = activeSections.first(where: { $0.id == id }) {
            depth += 1; parent = item.parentID
        }
        return depth
    }
    func insertionID(afterSection section: BookSection) -> String? {
        let ids = descendantIDs(of: section.id)
        let items = entries
        guard let index = items.firstIndex(where: { $0.id == "section:" + section.id.uuidString }) else { return nil }
        return items.dropFirst(index + 1).first { entry in
            if case .section(let value) = entry { return !ids.contains(value.id) }
            return false
        }?.id
    }
}

@Model final class BookSection {
    var id: UUID = UUID()
    var title: String = "New section"
    var rank: Double = 0
    var book: Notebook?
    var parentID: UUID?
    var colorName: String = "sage"
    var symbol: String = "bookmark"
    var dividerStyle: String = "tab"
    var trashedAt: Date?
    // Optional persisted additions can migrate old rows without a SQL default.
    @Attribute(originalName: "modifiedAt") var storedModifiedAt: Date?
    var modifiedAt: Date {
        get { storedModifiedAt ?? .distantPast }
        set { storedModifiedAt = newValue }
    }
    init(title: String, rank: Double, book: Notebook) {
        self.title = title; self.rank = rank; self.book = book; self.modifiedAt = .now
    }
}

enum BookEntry: Identifiable {
    case page(NotePage), section(BookSection)
    var id: String {
        switch self {
        case .page(let page): "page:" + page.id.uuidString
        case .section(let section): "section:" + section.id.uuidString
        }
    }
    var rank: Double {
        switch self { case .page(let page): page.rank; case .section(let section): section.rank }
    }
    var title: String {
        switch self { case .page(let page): page.title; case .section(let section): section.title }
    }
}
