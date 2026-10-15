import Foundation
import SwiftData

/// Immutable snapshots are separate records so concurrent edits don't overwrite history.
@Model final class PageRevision {
    var id: UUID = UUID()
    var pageID: UUID = UUID()
    var createdAt: Date = Date()
    var reason: String = "Edit"
    @Attribute(.externalStorage) var payload: Data = Data()
    init(page: NotePage, reason: String) {
        pageID = page.id; self.reason = reason
        payload = (try? JSONEncoder().encode(PageState(page))) ?? Data()
    }
}

/// Links contain identifiers only; they never copy image or ink data.
@Model final class PageLink {
    var id: UUID = UUID()
    var sourceID: UUID = UUID()
    var targetID: UUID = UUID()
    var createdAt: Date = Date()
    var removedAt: Date?
    init(source: UUID, target: UUID) { sourceID = source; targetID = target }
}

struct NormalizedRect: Codable, Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 1
    var height: Double = 1
    var clamped: Self {
        let w = min(1, max(0.04, width)), h = min(1, max(0.04, height))
        return Self(x: min(1 - w, max(0, x)), y: min(1 - h, max(0, y)), width: w, height: h)
    }
    func clockwise() -> Self { Self(x: 1 - y - height, y: x, width: height, height: width).clamped }
}

struct PagePhoto: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var data: Data
    var rect: NormalizedRect
}

struct ImageAdjustments: Codable, Equatable, Sendable {
    var crop = NormalizedRect()
    var straighten: Double = 0
    var brightness: Double = 0
    var contrast: Double = 1
    var filter: String = "original"
    init() {}
    init(data: Data) { self = (try? JSONDecoder().decode(Self.self, from: data)) ?? Self() }
    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }
}

struct RecallCover: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var rect = NormalizedRect(x: 0.15, y: 0.3, width: 0.7, height: 0.12)
    static func decode(_ data: Data) -> [Self] { (try? JSONDecoder().decode([Self].self, from: data)) ?? [] }
    static func encode(_ covers: [Self]) -> Data { (try? JSONEncoder().encode(covers)) ?? Data() }
}

struct PageState: Codable, Sendable {
    var title: String
    var text: String
    var tags: [String]
    var bookID: UUID?
    var sectionID: UUID?
    var rank: Double
    var rotation: Int
    var favourite: Bool
    var bookmarked: Bool
    var drawing: Data
    var photos: [PagePhoto]?
    var enhancements: Data
    var covers: Data
    var trashedAt: Date?
    init(_ page: NotePage) {
        title = page.title; text = page.text; tags = page.tags; bookID = page.book?.id
        sectionID = page.sectionID; rank = page.rank; rotation = page.rotation
        favourite = page.isFavourite; bookmarked = page.isBookmarked; drawing = page.drawingData
        photos = page.photoLayers
        enhancements = page.enhancementData; covers = page.revisionCoverData; trashedAt = page.trashedAt
    }
    @MainActor func apply(to page: NotePage, in context: ModelContext) {
        page.title = title; page.text = text; page.tags = tags; page.sectionID = sectionID
        page.rank = rank; page.rotation = rotation; page.isFavourite = favourite
        page.isBookmarked = bookmarked; page.drawingData = drawing; page.enhancementData = enhancements
        page.photoLayers = photos ?? []
        page.revisionCoverData = covers; page.trashedAt = trashedAt
        if page.book?.id != bookID {
            page.book = (try? context.fetch(FetchDescriptor<Notebook>()))?.first { $0.id == bookID }
        }
        if let book = page.book, let sectionID = page.sectionID, !book.activeSections.contains(where: { $0.id == sectionID }) { page.sectionID = nil }
        page.visualVersion = UUID(); page.modifiedAt = .now
    }
}
