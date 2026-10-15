import Foundation
import SwiftData
import Observation

@MainActor @Observable final class LibraryActions {
    private struct Command { let name: String; let undo: @MainActor () throws -> Void }
    private var history: [Command] = []
    var error: String?
    var noticeVisible = false
    private var noticeID = UUID()
    var undoTitle: String? { history.last?.name }
    func undo() {
        guard let command = history.popLast() else { return }
        noticeVisible = false
        do { try command.undo(); FolioStyle.haptic() } catch { self.error = error.localizedDescription }
    }
    func register(_ name: String, undo: @escaping @MainActor () throws -> Void) {
        history.append(Command(name: name, undo: undo))
        if history.count > 20 { history.removeFirst() }
        noticeID = UUID(); noticeVisible = true
        let token = noticeID
        Task {
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            if noticeID == token { noticeVisible = false }
        }
    }
    func edit(_ pages: [NotePage], in context: ModelContext, name: String, books: [Notebook] = [], mutation: () -> Void) {
        let previous = pages.map { ($0, PageState($0)) }
        let affected = books + pages.compactMap(\.book)
        let placements = affected.flatMap { $0.entries }.map(EntryPlacement.init)
        for page in pages { context.insert(PageRevision(page: page, reason: "Before " + name.lowercased())) }
        mutation()
        for (page, state) in previous {
            if page.rotation != state.rotation || page.drawingData != state.drawing || page.enhancementData != state.enhancements { page.visualVersion = UUID() }
            page.modifiedAt = .now
            context.insert(PageRevision(page: page, reason: name))
        }
        do {
            try context.save()
            register(name) {
                for (page, state) in previous where !page.isDeleted {
                    context.insert(PageRevision(page: page, reason: "Before undo"))
                    state.apply(to: page, in: context)
                }
                for placement in placements { placement.restore() }
                try context.save()
            }
            FolioStyle.haptic()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
    func rotate(_ pages: [NotePage], in context: ModelContext) {
        edit(pages, in: context, name: "Rotate pages") {
            for page in pages {
                page.rotation = (page.rotation + 1) % 4
                let covers = RecallCover.decode(page.revisionCoverData).map { cover in
                    var next = cover; next.rect = cover.rect.clockwise(); return next
                }
                page.revisionCoverData = RecallCover.encode(covers)
            }
        }
    }
    func trash(_ pages: [NotePage], in context: ModelContext) {
        edit(pages, in: context, name: "Delete pages") {
            for page in pages { page.trashedAt = .now }
        }
    }
    func duplicate(_ pages: [NotePage], in context: ModelContext) {
        var copies: [NotePage] = []
        for source in pages {
            let copy = source.copy(to: source.book)
            context.insert(copy)
            if let book = source.book {
                var entries = book.entries.filter { $0.id != "page:" + copy.id.uuidString }
                let index = entries.firstIndex { $0.id == "page:" + source.id.uuidString } ?? entries.count - 1
                entries.insert(.page(copy), at: min(entries.count, index + 1)); book.applyOrder(entries)
            }
            copies.append(copy)
        }
        do {
            try context.save()
            register("Duplicate pages") { for page in copies { page.trashedAt = .now; page.modifiedAt = .now }; try context.save() }
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
    func move(_ pages: [NotePage], to book: Notebook?, before entryID: String?, in context: ModelContext) {
        edit(pages, in: context, name: "Move pages", books: book.map { [$0] } ?? []) {
            for page in pages {
                page.book = book; page.sectionID = nil
                if let book { Self.place(page, in: book, before: entryID) }
                else { page.rank = Date.now.timeIntervalSince1970 }
            }
        }
    }
    static func place(_ page: NotePage, in book: Notebook, before entryID: String?) {
        var entries = book.entries.filter { $0.id != "page:" + page.id.uuidString }
        let index = entryID.flatMap { id in entries.firstIndex { $0.id == id } } ?? entries.count
        entries.insert(.page(page), at: index); book.applyOrder(entries)
    }
    func reorder(_ id: String, before target: String?, in book: Notebook, context: ModelContext) {
        let entries = book.entries
        guard let entry = entries.first(where: { $0.id == id }), id != target else { return }
        var moving: [BookEntry] = [entry]
        if case .section(let section) = entry {
            let ids = book.descendantIDs(of: section.id)
            moving = entries.filter {
                switch $0 {
                case .section(let value): ids.contains(value.id)
                case .page(let value): value.sectionID.map(ids.contains) == true
                }
            }
        }
        let movingIDs = Set(moving.map(\.id))
        guard target.map({ !movingIDs.contains($0) }) ?? true else { return }
        let placements = entries.map(EntryPlacement.init)
        var result = entries.filter { !movingIDs.contains($0.id) }
        let index = target.flatMap { id in result.firstIndex { $0.id == id } } ?? result.count
        result.insert(contentsOf: moving, at: index)
        // A subsection moved independently becomes a top-level divider. Its descendants stay attached.
        if case .section(let section) = entry { section.parentID = nil }
        book.applyOrder(result)
        do { try context.save(); register("Reorder pages") { placements.forEach { $0.restore() }; try context.save() } }
        catch { context.rollback(); error = error.localizedDescription }
    }
    func trashBook(_ book: Notebook, context: ModelContext) {
        book.trashedAt = .now; book.modifiedAt = .now
        do { try context.save(); register("Delete book") { book.trashedAt = nil; book.modifiedAt = .now; try context.save() } }
        catch { context.rollback(); error = error.localizedDescription }
    }
    func removeSection(_ section: BookSection, context: ModelContext) {
        guard let book = section.book else { return }
        let placements = book.entries.map(EntryPlacement.init)
        section.trashedAt = .now; section.modifiedAt = .now
        for child in book.activeSections where child.parentID == section.id { child.parentID = section.parentID }
        book.applyOrder(book.entries)
        do { try context.save(); register("Remove divider") { placements.forEach { $0.restore() }; try context.save() } }
        catch { context.rollback(); error = error.localizedDescription }
    }
}

@MainActor private struct EntryPlacement {
    let entry: BookEntry
    let rank: Double
    let section: UUID?
    let trashed: Date?
    init(_ entry: BookEntry) {
        self.entry = entry; rank = entry.rank
        switch entry {
        case .page(let value): section = value.sectionID; trashed = value.trashedAt
        case .section(let value): section = value.parentID; trashed = value.trashedAt
        }
    }
    func restore() {
        switch entry {
        case .page(let value): value.rank = rank; value.sectionID = section; value.trashedAt = trashed; value.modifiedAt = .now
        case .section(let value): value.rank = rank; value.parentID = section; value.trashedAt = trashed; value.modifiedAt = .now
        }
    }
}
