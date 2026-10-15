import Foundation
import SwiftData
import Observation
import UIKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct BookArchive: Codable, Sendable {
    var id: UUID; var title: String; var color: String; var secondColor: String
    var symbol: String; var style: String; var spine: String; var texture: Double
    var created: Date; var modified: Date; var locked: Bool; var trashed: Date?
    init(_ book: Notebook) {
        id = book.id; title = book.title; color = book.colorName; secondColor = book.gradientColorName
        symbol = book.symbol; style = book.coverStyle; spine = book.spineLabel; texture = book.textureStrength
        created = book.createdAt; modified = book.modifiedAt; locked = book.isLocked; trashed = book.trashedAt
    }
    func apply(_ book: Notebook) {
        book.id = id; book.title = title; book.colorName = color; book.gradientColorName = secondColor
        book.symbol = symbol; book.coverStyle = style; book.spineLabel = spine; book.textureStrength = texture
        book.createdAt = created; book.modifiedAt = modified; book.isLocked = locked; book.trashedAt = trashed
    }
}
struct SectionArchive: Codable, Sendable {
    var id: UUID; var bookID: UUID?; var title: String; var rank: Double; var parent: UUID?
    var color: String; var symbol: String; var style: String; var trashed: Date?; var modified: Date
    init(_ section: BookSection) {
        id = section.id; bookID = section.book?.id; title = section.title; rank = section.rank
        parent = section.parentID; color = section.colorName; symbol = section.symbol
        style = section.dividerStyle; trashed = section.trashedAt; modified = section.modifiedAt
    }
    func apply(_ section: BookSection) {
        section.id = id; section.title = title; section.rank = rank; section.parentID = parent
        section.colorName = color; section.symbol = symbol; section.dividerStyle = style
        section.trashedAt = trashed; section.modifiedAt = modified
    }
}
struct ArchivedPage: Codable, Sendable {
    var id: UUID; var state: PageState; var created: Date; var modified: Date
    var detected: Date?; var viewed: Date?; var recognition: String; var confidence: Double; var suggestion: String
    init(_ page: NotePage) {
        id = page.id; state = PageState(page); created = page.createdAt; modified = page.modifiedAt
        detected = page.detectedDate; viewed = page.lastViewedAt; recognition = page.recognitionState
        confidence = page.recognitionConfidence; suggestion = page.suggestedSection
    }
}
struct RevisionArchive: Codable, Sendable {
    var id: UUID; var pageID: UUID; var date: Date; var reason: String; var payload: Data
    init(_ revision: PageRevision) { id = revision.id; pageID = revision.pageID; date = revision.createdAt; reason = revision.reason; payload = revision.payload }
}
struct LinkArchive: Codable, Sendable {
    var id: UUID; var source: UUID; var target: UUID; var created: Date; var removed: Date?
    init(_ link: PageLink) { id = link.id; source = link.sourceID; target = link.targetID; created = link.createdAt; removed = link.removedAt }
}
struct FolderManifest: Codable, Sendable {
    var format = 2
    var savedAt = Date()
    var books: [BookArchive]
    var sections: [SectionArchive]
    var pages: [UUID]
    var pageRecords: [String: String]
    var revisions: [UUID]
    var links: [LinkArchive]
}

enum WorkspaceError: LocalizedError {
    case permission, unsupported, missingPage, changed
    var errorDescription: String? {
        switch self {
        case .permission: "This folder isn’t accessible. Select it again in Files."
        case .unsupported: "This folder contains a library format that this version of Folio can’t open."
        case .missingPage: "A page file is missing from the folder. Keep the folder available offline in Files, then try again. The local library is unchanged."
        case .changed: "The folder changed while saving. Reconnect it to merge those changes before saving again."
        }
    }
}

private final class CoordinatedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<Value, Error> = .failure(WorkspaceError.permission)
    func set(_ result: Result<Value, Error>) { lock.lock(); value = result; lock.unlock() }
    func get() throws -> Value { lock.lock(); defer { lock.unlock() }; return try value.get() }
}

/// Originals are immutable files. Metadata writes are coordinated and atomic.
/// The manifest is committed last; no archive file is removed by a save.
actor FolderArchive {
    static let shared = FolderArchive()
    private func root(_ folder: URL) -> URL { folder.appending(path: "Folio Library", directoryHint: .isDirectory) }
    func manifest(in folder: URL) throws -> FolderManifest? {
        let path = root(folder).appending(path: "Library.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let result = try JSONDecoder().decode(FolderManifest.self, from: read(path))
        guard result.format == 2 else { throw WorkspaceError.unsupported }
        return result
    }
    func prepare(_ folder: URL) throws {
        var coordinationError: NSError?
        let result = CoordinatedValue<Void>()
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: folder, options: [], error: &coordinationError) { coordinated in
            result.set(Result {
                for name in ["originals", "pages", "revisions"] {
                    try FileManager.default.createDirectory(at: coordinated.appending(path: "Folio Library/\(name)", directoryHint: .isDirectory), withIntermediateDirectories: true)
                }
            })
        }
        if let coordinationError { throw coordinationError }; try result.get()
    }
    func existingOriginals(in folder: URL) throws -> Set<UUID> {
        let directory = root(folder).appending(path: "originals")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return Set(files.compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) })
    }
    private static let originalExtensions = ["image", "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp", "avif", "jp2", "dng"]
    private func originalURL(_ id: UUID, folder: URL) -> URL? {
        for ext in Self.originalExtensions {
            let url = root(folder).appending(path: "originals/\(id.uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
    func writePage(_ page: ArchivedPage, original: Data?, folder: URL) throws -> String {
        if originalURL(page.id, folder: folder) == nil {
            guard let original else { throw WorkspaceError.missingPage }
            var ext = "image"
            if let source = CGImageSourceCreateWithData(original as CFData, nil), let type = CGImageSourceGetType(source),
               let preferred = UTType(type as String)?.preferredFilenameExtension, Self.originalExtensions.contains(preferred) { ext = preferred }
            try write(original, to: root(folder).appending(path: "originals/\(page.id.uuidString).\(ext)"))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(page)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let url = root(folder).appending(path: "pages/\(hash).json")
        if !FileManager.default.fileExists(atPath: url.path) { try write(data, to: url) }
        return hash
    }
    func page(_ id: UUID, manifest: FolderManifest, folder: URL) throws -> (ArchivedPage, Data) {
        do {
            guard let hash = manifest.pageRecords[id.uuidString], hash.count == 64,
                  hash.allSatisfy({ $0.isHexDigit }) else { throw WorkspaceError.missingPage }
            let metadata = try read(root(folder).appending(path: "pages/\(hash).json"))
            let actual = SHA256.hash(data: metadata).map { String(format: "%02x", $0) }.joined()
            guard actual == hash else { throw WorkspaceError.missingPage }
            let meta = try JSONDecoder().decode(ArchivedPage.self, from: metadata)
            guard meta.id == id else { throw WorkspaceError.missingPage }
            guard let source = originalURL(id, folder: folder) else { throw WorkspaceError.missingPage }
            let original = try read(source)
            guard !original.isEmpty else { throw WorkspaceError.missingPage }
            return (meta, original)
        } catch { throw WorkspaceError.missingPage }
    }
    func validate(_ manifest: FolderManifest, folder: URL) throws {
        // Check every record before changing the local store. Decode one at a time.
        for id in manifest.pages { _ = try page(id, manifest: manifest, folder: folder) }
        for id in manifest.revisions { _ = try revision(id, folder: folder) }
    }
    func existingRevisions(in folder: URL) throws -> Set<UUID> {
        let files = try FileManager.default.contentsOfDirectory(at: root(folder).appending(path: "revisions"), includingPropertiesForKeys: nil)
        return Set(files.compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) })
    }
    func writeRevision(_ revision: RevisionArchive, folder: URL) throws {
        try writeJSON(revision, to: root(folder).appending(path: "revisions/\(revision.id.uuidString).json"))
    }
    func revision(_ id: UUID, folder: URL) throws -> RevisionArchive {
        try JSONDecoder().decode(RevisionArchive.self, from: read(root(folder).appending(path: "revisions/\(id.uuidString).json")))
    }
    func commit(_ manifest: FolderManifest, folder: URL, expected: Date?) throws {
        let url = root(folder).appending(path: "Library.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        var coordinationError: NSError?
        let result = CoordinatedValue<Void>()
        let exists = FileManager.default.fileExists(atPath: url.path)
        let item = exists ? url : url.deletingLastPathComponent()
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: item, options: exists ? .forReplacing : [], error: &coordinationError) { coordinated in
            let target = exists ? coordinated : coordinated.appending(path: url.lastPathComponent)
            result.set(Result {
                if FileManager.default.fileExists(atPath: target.path) {
                    let current = try JSONDecoder().decode(FolderManifest.self, from: Data(contentsOf: target))
                    guard current.savedAt == expected else { throw WorkspaceError.changed }
                } else if expected != nil { throw WorkspaceError.changed }
                try data.write(to: target, options: .atomic)
            })
        }
        if let coordinationError { throw coordinationError }; try result.get()
    }
    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        if FileManager.default.fileExists(atPath: url.path), (try? read(url)) == data { return }
        try write(data, to: url)
    }
    private func read(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        let result = CoordinatedValue<Data>()
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result.set(Result { try Data(contentsOf: coordinated) })
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
    private func write(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        let result = CoordinatedValue<Void>()
        let exists = FileManager.default.fileExists(atPath: url.path)
        let item = exists ? url : url.deletingLastPathComponent()
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: item, options: exists ? .forReplacing : [], error: &coordinationError) { coordinated in
            let target = exists ? coordinated : coordinated.appending(path: url.lastPathComponent)
            result.set(Result { try data.write(to: target, options: .atomic) })
        }
        if let coordinationError { throw coordinationError }; try result.get()
    }
}

/// Keep a Files-provider grant alive until disconnect or replacement. A value
/// owner also balances access if a connection attempt throws.
private final class FolderAccess {
    let url: URL
    init?(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        self.url = url
    }
    deinit { url.stopAccessingSecurityScopedResource() }
}

@MainActor @Observable final class WorkspaceFolder {
    var folderName: String? = UserDefaults.standard.string(forKey: "workspaceName")
    var lastSaved: Date?
    var busy = false
    var restoring = false
    var error: String?
    private var folder: URL?
    private var folderAccess: FolderAccess?
    private var pending: Task<Void, Never>?
    private var expectedDate: Date?
    private var dirty = false
    private var pageCache: [UUID: (modified: Date, viewed: Date?, record: String)] = [:]
    var isConnected: Bool { folder != nil }
    func resume(context: ModelContext) async {
        guard folder == nil, let data = UserDefaults.standard.data(forKey: "workspaceBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            try await connect(url, context: context)
        } catch { self.error = error.localizedDescription }
    }
    func connect(_ url: URL, context: ModelContext) async throws {
        guard !busy else { return }
        busy = true; defer { busy = false; restoring = false }
        let access = FolderAccess(url)
        pageCache.removeAll()
        let manifest = try await FolderArchive.shared.manifest(in: url)
        if let manifest {
            restoring = true
            try await FolderArchive.shared.validate(manifest, folder: url)
            let autosave = context.autosaveEnabled
            context.autosaveEnabled = false
            do { try await merge(manifest, folder: url, context: context) }
            catch { context.rollback(); context.autosaveEnabled = autosave; throw error }
            context.autosaveEnabled = autosave
            expectedDate = manifest.savedAt; lastSaved = manifest.savedAt
        } else { expectedDate = nil }
        let bookmark = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: "workspaceBookmark")
        UserDefaults.standard.set(url.lastPathComponent, forKey: "workspaceName")
        folderAccess = access
        folder = url; folderName = url.lastPathComponent
        LibraryPersistence.observe(self, context: context)
        dirty = true
        // Save immediately after attach/restore, without requiring another edit.
        busy = false
        await saveNow(context: context)
    }
    func disconnect() {
        LibraryPersistence.stopObserving(self)
        folderAccess = nil
        pending?.cancel(); folder = nil; folderName = nil; expectedDate = nil; pageCache.removeAll()
        UserDefaults.standard.removeObject(forKey: "workspaceBookmark")
        UserDefaults.standard.removeObject(forKey: "workspaceName")
    }
    func schedule(context: ModelContext) {
        guard folder != nil else { return }
        dirty = true
        guard !busy else { return }
        pending?.cancel()
        pending = Task {
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            pending = nil // This task is now a writer, no longer a cancellable timer.
            await saveNow(context: context)
        }
    }
    func saveNow(context: ModelContext) async {
        guard let folder else { return }
        guard !busy else { dirty = true; return }
        pending?.cancel(); pending = nil
        busy = true; dirty = false
        let background = UIApplication.shared.beginBackgroundTask(withName: "Save working folder")
        defer {
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
            busy = false
            if dirty { schedule(context: context) }
        }
        do {
            let remote = try await FolderArchive.shared.manifest(in: folder)
            if let remote, remote.savedAt != expectedDate { throw WorkspaceError.changed }
            try await FolderArchive.shared.prepare(folder)
            let books = try context.fetch(FetchDescriptor<Notebook>()).map(BookArchive.init)
            let sections = try context.fetch(FetchDescriptor<BookSection>()).map(SectionArchive.init)
            let pages = try context.fetch(FetchDescriptor<NotePage>())
            let revisions = try context.fetch(FetchDescriptor<PageRevision>())
            let links = try context.fetch(FetchDescriptor<PageLink>()).map(LinkArchive.init)
            let existing = try await FolderArchive.shared.existingOriginals(in: folder)
            var records: [String: String] = [:]
            for page in pages where page.modelContext != nil && !page.isDeleted {
                let id = page.id
                if existing.contains(id), let cached = pageCache[id], cached.modified == page.modifiedAt, cached.viewed == page.lastViewedAt {
                    records[id.uuidString] = cached.record
                } else {
                    let captured = ArchivedPage(page)
                    let original = existing.contains(id) ? nil : page.imageData
                    let record = try await FolderArchive.shared.writePage(captured, original: original, folder: folder)
                    records[id.uuidString] = record
                    pageCache[id] = (captured.modified, captured.viewed, record)
                }
            }
            let savedRevisions = try await FolderArchive.shared.existingRevisions(in: folder)
            var revisionIDs: [UUID] = []
            for revision in revisions where revision.modelContext != nil && !revision.isDeleted {
                let id = revision.id
                if !savedRevisions.contains(id) { try await FolderArchive.shared.writeRevision(RevisionArchive(revision), folder: folder) }
                revisionIDs.append(id)
            }
            let index = FolderManifest(books: books.sorted { $0.id.uuidString < $1.id.uuidString },
                sections: sections.sorted { $0.id.uuidString < $1.id.uuidString },
                pages: records.keys.compactMap { UUID(uuidString: $0) }.sorted { $0.uuidString < $1.uuidString }, pageRecords: records,
                revisions: revisionIDs.sorted { $0.uuidString < $1.uuidString },
                links: links.sorted { $0.id.uuidString < $1.id.uuidString })
            var unchanged = false
            if let remote {
                var comparable = index; comparable.savedAt = remote.savedAt
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                unchanged = try encoder.encode(comparable) == encoder.encode(remote)
            }
            if !unchanged { try await FolderArchive.shared.commit(index, folder: folder, expected: expectedDate) }
            lastSaved = unchanged ? remote?.savedAt : index.savedAt
            expectedDate = lastSaved; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func merge(_ manifest: FolderManifest, folder: URL, context: ModelContext) async throws {
        var books = Dictionary(try context.fetch(FetchDescriptor<Notebook>()).map { ($0.id, $0) }, uniquingKeysWith: { $0.modifiedAt >= $1.modifiedAt ? $0 : $1 })
        for archived in manifest.books {
            let book = books[archived.id] ?? Notebook(title: archived.title)
            if books[archived.id] == nil { context.insert(book); archived.apply(book); books[archived.id] = book }
            else if archived.modified > book.modifiedAt { archived.apply(book) }
        }
        var sections = Dictionary(try context.fetch(FetchDescriptor<BookSection>()).map { ($0.id, $0) }, uniquingKeysWith: { $0.modifiedAt >= $1.modifiedAt ? $0 : $1 })
        for archived in manifest.sections {
            guard let bookID = archived.bookID, let book = books[bookID] else { continue }
            let section = sections[archived.id] ?? BookSection(title: archived.title, rank: archived.rank, book: book)
            if sections[archived.id] == nil { context.insert(section); archived.apply(section); sections[archived.id] = section }
            else if archived.modified > section.modifiedAt { archived.apply(section) }
        }
        var pages = Dictionary(try context.fetch(FetchDescriptor<NotePage>()).map { ($0.id, $0) }, uniquingKeysWith: { $0.modifiedAt >= $1.modifiedAt ? $0 : $1 })
        for id in manifest.pages {
            let (archived, original) = try await FolderArchive.shared.page(id, manifest: manifest, folder: folder)
            let existing = pages[id]
            let page = existing ?? NotePage(imageData: original, thumbnailData: Data(), rank: archived.state.rank, book: archived.state.bookID.flatMap { books[$0] })
            if existing == nil { context.insert(page); page.id = id; pages[id] = page }
            if existing == nil || archived.modified > page.modifiedAt {
                if existing != nil { context.insert(PageRevision(page: page, reason: "Before folder restore")) }
                archived.state.apply(to: page, in: context)
                page.createdAt = archived.created; page.modifiedAt = archived.modified; page.detectedDate = archived.detected
                page.lastViewedAt = archived.viewed; page.recognitionState = archived.recognition
                page.recognitionConfidence = archived.confidence; page.suggestedSection = archived.suggestion
            } else if archived.modified < page.modifiedAt {
                let revision = PageRevision(page: page, reason: "Version from working folder")
                revision.payload = try JSONEncoder().encode(archived.state); context.insert(revision)
            }
        }
        let knownRevisions = Set(try context.fetch(FetchDescriptor<PageRevision>()).map(\.id))
        for id in manifest.revisions where !knownRevisions.contains(id) {
            let archived = try await FolderArchive.shared.revision(id, folder: folder)
            guard let page = pages[archived.pageID] else { continue }
            let revision = PageRevision(page: page, reason: archived.reason)
            revision.id = archived.id; revision.createdAt = archived.date; revision.payload = archived.payload; context.insert(revision)
        }
        let knownLinks = try context.fetch(FetchDescriptor<PageLink>())
        for archived in manifest.links {
            if let link = knownLinks.first(where: { $0.id == archived.id }) {
                if let removed = archived.removed, removed > (link.removedAt ?? .distantPast) { link.removedAt = removed }
            } else {
                let link = PageLink(source: archived.source, target: archived.target)
                link.id = archived.id; link.createdAt = archived.created; link.removedAt = archived.removed; context.insert(link)
            }
        }
        do { try LibraryReconciler.run(context); try LibraryPersistence.save(context) } catch { context.rollback(); throw error }
    }
}
