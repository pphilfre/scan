import Foundation
import SwiftData

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
    var isBookmarked: Bool = false
    var trashedAt: Date?
    // Optional persisted additions can migrate old rows without a SQL default.
    @Attribute(originalName: "modifiedAt") var storedModifiedAt: Date?
    var modifiedAt: Date {
        get { storedModifiedAt ?? createdAt }
        set { storedModifiedAt = newValue }
    }
    @Attribute(originalName: "visualVersion") var storedVisualVersion: UUID?
    var visualVersion: UUID {
        get { storedVisualVersion ?? id }
        set { storedVisualVersion = newValue }
    }
    var thumbnailVersion: UUID?
    @Attribute(.externalStorage, originalName: "enhancementData") var storedEnhancementData: Data?
    var enhancementData: Data {
        get { storedEnhancementData ?? Data() }
        set { storedEnhancementData = newValue }
    }
    @Attribute(.externalStorage, originalName: "revisionCoverData") var storedRevisionCoverData: Data?
    var revisionCoverData: Data {
        get { storedRevisionCoverData ?? Data() }
        set { storedRevisionCoverData = newValue }
    }


    init(imageData: Data, thumbnailData: Data, rank: Double, book: Notebook? = nil) {
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.rank = rank
        self.book = book
    }
    func copy(to destination: Notebook?) -> NotePage {
        let page = NotePage(imageData: imageData, thumbnailData: thumbnailData, rank: destination?.nextRank ?? rank + 1, book: destination)
        page.title = title + " copy"
        page.text = text
        page.rotation = rotation
        page.tags = tags
        page.drawingData = drawingData
        page.detectedDate = detectedDate
        page.recognitionState = recognitionState
        page.recognitionConfidence = recognitionConfidence
        page.suggestedSection = suggestedSection
        page.enhancementData = enhancementData
        page.revisionCoverData = revisionCoverData
        page.visualVersion = visualVersion
        page.thumbnailVersion = thumbnailVersion
        page.isBookmarked = isBookmarked
        page.sectionID = (destination?.sections ?? []).filter { !$0.isDeleted && $0.rank < page.rank }
            .max(by: { $0.rank < $1.rank })?.id
        return page
    }
}
