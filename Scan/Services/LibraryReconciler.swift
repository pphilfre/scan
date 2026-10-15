import Foundation
import SwiftData

/// Folder restores on two devices may later arrive as separate CloudKit records
/// with the same app UUID. Consolidate identifiers and retain competing edits.
@MainActor enum LibraryReconciler {
    static func run(_ context: ModelContext) throws {
        try StudyStore.reconcile(context)
        let books = try context.fetch(FetchDescriptor<Notebook>())
        for group in Dictionary(grouping: books, by: \.id).values where group.count > 1 {
            let sorted = group.sorted { $0.modifiedAt > $1.modifiedAt }
            guard let keep = sorted.first else { continue }
            keep.isLocked = group.contains(where: \.isLocked)
            for duplicate in sorted.dropFirst() {
                for page in duplicate.pages ?? [] { page.book = keep }
                for section in duplicate.sections ?? [] { section.book = keep }
                context.delete(duplicate)
            }
        }
        let sections = try context.fetch(FetchDescriptor<BookSection>())
        for group in Dictionary(grouping: sections.filter { !$0.isDeleted }, by: \.id).values where group.count > 1 {
            let sorted = group.sorted { $0.modifiedAt > $1.modifiedAt }
            for duplicate in sorted.dropFirst() { context.delete(duplicate) }
        }
        for book in try context.fetch(FetchDescriptor<Notebook>()) where !book.isDeleted {
            let sectionIDs = Set(book.activeSections.map(\.id))
            for section in book.activeSections {
                if let parent = section.parentID, !sectionIDs.contains(parent) { section.parentID = nil; section.modifiedAt = .now }
                var visited: Set<UUID> = [section.id]
                var parent = section.parentID
                while let id = parent {
                    if !visited.insert(id).inserted { section.parentID = nil; section.modifiedAt = .now; break }
                    parent = book.activeSections.first { $0.id == id }?.parentID
                }
            }
            if book.orderedPages.contains(where: { $0.sectionID.map { !sectionIDs.contains($0) } == true }) { book.applyOrder(book.entries) }
        }
        let pages = try context.fetch(FetchDescriptor<NotePage>())
        for group in Dictionary(grouping: pages.filter { !$0.isDeleted }, by: \.id).values where group.count > 1 {
            let sorted = group.sorted { $0.modifiedAt > $1.modifiedAt }
            guard let keep = sorted.first else { continue }
            for duplicate in sorted.dropFirst() {
                if duplicate.imageData != keep.imageData {
                    // A UUID collision must never discard a different original.
                    duplicate.id = UUID(); duplicate.title = "Recovered " + duplicate.title
                } else {
                    context.insert(PageRevision(page: duplicate, reason: "Concurrent version"))
                    context.delete(duplicate)
                }
            }
        }
        let revisions = try context.fetch(FetchDescriptor<PageRevision>())
        for group in Dictionary(grouping: revisions, by: \.id).values where group.count > 1 {
            guard let keep = group.first else { continue }
            for duplicate in group.dropFirst() {
                if duplicate.payload == keep.payload { context.delete(duplicate) }
                else { duplicate.id = UUID() }
            }
        }
        let links = try context.fetch(FetchDescriptor<PageLink>())
        for group in Dictionary(grouping: links, by: \.id).values where group.count > 1 {
            guard let keep = group.first else { continue }
            keep.removedAt = group.compactMap(\.removedAt).max()
            for duplicate in group.dropFirst() { context.delete(duplicate) }
        }
        if context.hasChanges { try LibraryPersistence.save(context) }
    }
}
