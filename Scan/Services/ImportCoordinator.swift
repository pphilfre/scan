import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

@MainActor @Observable final class ImportCoordinator {
    var isBusy = false
    var progress = ""
    var error: String?
    private var job: Task<Void, Never>?
    private var resuming = false
    func cancel() { job?.cancel() }

    func importScans(_ images: [UIImage], into book: Notebook?, before entryID: String? = nil, context: ModelContext) {
        start() {
            for (index, image) in images.enumerated() {
                try Task.checkCancellation()
                self.progress = "Saving page \(index + 1) of \(images.count)…"
                let prepared = try await DocumentProcessor.shared.prepareScan(ImmutableScanImage(image: image))
                try await self.insert(prepared, into: book, before: entryID, context: context)
            }
        }
    }
    func importPhotos(_ items: [PhotosPickerItem], into book: Notebook?, before entryID: String? = nil, context: ModelContext) {
        start() {
            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                self.progress = "Importing photo \(index + 1) of \(items.count)…"
                guard let data = try await item.loadTransferable(type: Data.self) else { throw DocumentError.unreadable }
                let prepared = try await DocumentProcessor.shared.prepare(data)
                try await self.insert(prepared, into: book, before: entryID, context: context)
            }
        }
    }
    func importFiles(_ urls: [URL], into book: Notebook?, before entryID: String? = nil, context: ModelContext) {
        start() {
            for url in urls {
                try Task.checkCancellation()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if url.pathExtension.lowercased() == "pdf" {
                    let count = try await DocumentProcessor.shared.pdfPageCount(at: url)
                    for index in 0..<count {
                        try Task.checkCancellation()
                        self.progress = "Importing PDF page \(index + 1) of \(count)…"
                        let prepared = try await DocumentProcessor.shared.renderPDFPage(at: url, index: index)
                        try await self.insert(prepared, into: book, before: entryID, context: context)
                    }
                } else {
                    self.progress = "Importing \(url.lastPathComponent)…"
                    let data = try await Task.detached { try Data(contentsOf: url) }.value
                    let prepared = try await DocumentProcessor.shared.prepare(data)
                    try await self.insert(prepared, into: book, before: entryID, context: context)
                }
            }
        }
    }
    private func start(operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        job = Task {
            defer { isBusy = false; progress = ""; job = nil }
            do { try await operation() }
            catch is CancellationError { /* Already saved pages remain in the library. */ }
            catch { self.error = error.localizedDescription }
        }
    }
    private func insert(_ prepared: PreparedPage, into book: Notebook?, before entryID: String? = nil, context: ModelContext) async throws {
        try Task.checkCancellation()
        guard book?.isDeleted != true, book?.trashedAt == nil else { throw CancellationError() }
        let page = NotePage(imageData: prepared.original, thumbnailData: prepared.thumbnail, rank: book?.nextRank ?? Date.now.timeIntervalSince1970, book: book)
        context.insert(page)
        if let book { LibraryActions.place(page, in: book, before: entryID) }
        try context.save() // Preserve the image before attempting recognition.
        progress = "Recognising handwriting on device…"
        await recognise(page, context: context)
    }
    func recognise(_ page: NotePage, context: ModelContext) async {
        page.recognitionState = "recognising"
        do {
            let originalText = page.text
            let originalTitle = page.title
            let rotation = page.rotation
            let result = try await DocumentProcessor.shared.recognise(page.imageData, rotation: rotation,
                vocabulary: [page.book?.title ?? ""] + page.tags)
            guard !page.isDeleted else { return }
            if page.rotation != rotation {
                page.recognitionState = "pending"
                await recognise(page, context: context)
                return
            }
            context.insert(PageRevision(page: page, reason: "Before recognition"))
            if page.text == originalText { page.text = result.text }
            if page.title == originalTitle && page.title == "Untitled note" { page.title = SmartMetadata.title(from: result.text) }
            page.detectedDate = SmartMetadata.date(from: result.text)
            page.suggestedSection = SmartMetadata.section(from: result.text)
            page.recognitionConfidence = result.confidence
            page.recognitionState = result.text.isEmpty ? "empty" : "complete"
            page.modifiedAt = .now
            context.insert(PageRevision(page: page, reason: "Text recognition"))
            try context.save()
        } catch {
            guard !page.isDeleted else { return }
            page.recognitionState = "failed"; page.modifiedAt = .now
            try? context.save()
            self.error = "The original page is saved. Text recognition couldn’t finish: " + error.localizedDescription
        }
    }
    func resumePending(context: ModelContext) async {
        guard !resuming, !isBusy else { return }
        resuming = true; defer { resuming = false }
        let descriptor = FetchDescriptor<NotePage>(predicate: #Predicate { $0.recognitionState == "pending" || $0.recognitionState == "recognising" })
        guard let pages = try? context.fetch(descriptor) else { return }
        for page in pages where page.trashedAt == nil && page.book?.trashedAt == nil {
            if Task.isCancelled { return }
            await recognise(page, context: context)
        }
    }
}
