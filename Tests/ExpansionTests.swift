import XCTest
import SwiftData
import UIKit
@testable import Folio

final class ExpansionTests: XCTestCase {
    @MainActor private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Notebook.self, BookSection.self, NotePage.self, PageRevision.self, PageLink.self])
        let config: ModelConfiguration
        if let url { config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none) }
        return try ModelContainer(for: schema, configurations: [config])
    }
    @MainActor func testOriginalStoreMigratesWithoutLosingScansOrInk() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Original.store")
        let ids: (UUID, UUID, UUID) = try autoreleasepool {
            let schema = Schema([OriginalFolio.Notebook.self, OriginalFolio.NotePage.self, OriginalFolio.BookSection.self])
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, configurations: [config])
            let book = OriginalFolio.Notebook(title: "Existing notes", colorName: "plum", symbol: "atom")
            old.mainContext.insert(book)
            let section = OriginalFolio.BookSection(title: "Old divider", rank: 0, book: book)
            old.mainContext.insert(section)
            let page = OriginalFolio.NotePage(imageData: Data([4, 5, 6]), thumbnailData: Data([7]), rank: 1, book: book)
            page.text = "Corrected handwriting"; page.title = "Preserve me"; page.drawingData = Data([8, 9])
            page.tags = ["Revision"]; page.rotation = 1; page.sectionID = section.id
            old.mainContext.insert(page); try old.mainContext.save()
            return (book.id, section.id, page.id)
        }
        let updated = try container(url: url)
        let page = try XCTUnwrap(updated.mainContext.fetch(FetchDescriptor<NotePage>()).first)
        XCTAssertEqual(page.id, ids.2); XCTAssertEqual(page.book?.id, ids.0); XCTAssertEqual(page.sectionID, ids.1)
        XCTAssertEqual(page.imageData, Data([4, 5, 6])); XCTAssertEqual(page.drawingData, Data([8, 9]))
        XCTAssertEqual(page.text, "Corrected handwriting"); XCTAssertEqual(page.tags, ["Revision"])
        XCTAssertEqual(page.rotation, 1); XCTAssertFalse(page.isBookmarked); XCTAssertNil(page.trashedAt)
        XCTAssertEqual(ImageAdjustments(data: page.enhancementData), ImageAdjustments())
    }
    @MainActor func testExpandedStoreUpgradePreservesEnhancementsAndVersions() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Expanded.store")
        let version = UUID(), modified = Date(timeIntervalSince1970: 1_700_000_000)
        let pageID: UUID = try autoreleasepool {
            let schema = Schema([ExpandedFolio.Notebook.self, ExpandedFolio.NotePage.self, ExpandedFolio.BookSection.self, PageRevision.self, PageLink.self])
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, configurations: [config])
            let book = ExpandedFolio.Notebook(title: "Existing expanded notes"); book.modifiedAt = modified
            old.mainContext.insert(book)
            let page = ExpandedFolio.NotePage(imageData: Data([4, 5, 6]), thumbnailData: Data([7]), rank: 0, book: book)
            page.enhancementData = Data([10, 11]); page.revisionCoverData = Data([12, 13])
            page.visualVersion = version; page.modifiedAt = modified; page.isBookmarked = true
            old.mainContext.insert(page); try old.mainContext.save()
            return page.id
        }
        let updated = try container(url: url)
        let page = try XCTUnwrap(updated.mainContext.fetch(FetchDescriptor<NotePage>()).first)
        XCTAssertEqual(page.id, pageID); XCTAssertEqual(page.imageData, Data([4, 5, 6]))
        XCTAssertEqual(page.enhancementData, Data([10, 11])); XCTAssertEqual(page.revisionCoverData, Data([12, 13]))
        XCTAssertEqual(page.visualVersion, version); XCTAssertEqual(page.modifiedAt, modified)
        XCTAssertEqual(page.book?.modifiedAt, modified); XCTAssertTrue(page.isBookmarked)
    }
    @MainActor func testImportSavesBeforeFilingAndAutomaticallyWritesWorkingFolder() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let oldBookmark = defaults.data(forKey: "workspaceBookmark"), oldName = defaults.string(forKey: "workspaceName")
        let workspace = WorkspaceFolder()
        defer {
            workspace.disconnect()
            try? FileManager.default.removeItem(at: directory)
            defaults.set(oldBookmark, forKey: "workspaceBookmark"); defaults.set(oldName, forKey: "workspaceName")
        }
        let store = try container(); let context = store.mainContext
        let book = Notebook(title: "Destination"); context.insert(book)
        let existing = NotePage(imageData: Data([1]), thumbnailData: Data(), rank: 0, book: book)
        context.insert(existing); try context.save()
        try await workspace.connect(directory, context: context)
        let prepared = try await PageTemplates.shared.make("Lined")
        let url = directory.appending(path: "Scan.png"); try prepared.original.write(to: url)
        let importer = ImportCoordinator()
        var batch: [NotePage] = []
        importer.importFiles([url], into: nil, context: context) { saved in
            batch = saved
            // This is the same moment the UI offers the destination prompt.
            XCTAssertEqual(saved.count, 1); XCTAssertNil(saved.first?.book)
            XCTAssertEqual(saved.first?.recognitionState, "pending")
        }
        for _ in 0..<200 where batch.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(batch.count, 1)
        let page = try XCTUnwrap(batch.first)
        let id = page.id
        // Do not call saveNow: importing must trigger the automatic path itself.
        var archived: FolderManifest?
        for _ in 0..<100 {
            archived = try await FolderArchive.shared.manifest(in: directory)
            if archived?.pages.contains(id) == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let saved = try XCTUnwrap(archived)
        XCTAssertTrue(saved.pages.contains(id), workspace.error ?? "Import never reached working folder")
        let (_, original) = try await FolderArchive.shared.page(id, manifest: saved, folder: directory)
        XCTAssertEqual(original, prepared.original)
        let originals = try FileManager.default.contentsOfDirectory(at: directory.appending(path: "Folio Library/originals"), includingPropertiesForKeys: nil)
        XCTAssertTrue(originals.contains { $0.deletingPathExtension().lastPathComponent == id.uuidString && ["jpg", "jpeg"].contains($0.pathExtension) })
        let actions = LibraryActions()
        actions.move([page], to: book, before: "page:" + existing.id.uuidString, in: context)
        XCTAssertEqual(book.orderedPages.map(\.id), [id, existing.id])
        for _ in 0..<100 {
            let latest = try await FolderArchive.shared.manifest(in: directory)
            if let latest {
                let (record, _) = try await FolderArchive.shared.page(id, manifest: latest, folder: directory)
                if record.state.bookID == book.id { archived = latest; break }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let latest = try XCTUnwrap(archived)
        let (record, _) = try await FolderArchive.shared.page(id, manifest: latest, folder: directory)
        XCTAssertEqual(record.state.bookID, book.id)
        // Finish OCR before the store is released; the original stays untouched.
        for _ in 0..<200 where importer.isBusy { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(importer.isBusy)
    }
    @MainActor func testSelectedPDFKeepsRequestedOrderAndCount() async throws {
        let store = try container(); let context = store.mainContext
        let prepared = try await PageTemplates.shared.make("Blank")
        var pages: [NotePage] = []
        for index in 0..<3 {
            let page = NotePage(imageData: prepared.original, thumbnailData: prepared.thumbnail, rank: Double(index))
            context.insert(page); pages.append(page)
        }
        pages[2].rotation = 1; try context.save()
        let url = try await PDFExporter.shared.export(pageIDs: [pages[2].id, pages[0].id], container: store, title: "Selection")
        defer { try? FileManager.default.removeItem(at: url) }
        let count = try await DocumentProcessor.shared.pdfPageCount(at: url)
        XCTAssertEqual(count, 2)
        let first = try await DocumentProcessor.shared.renderPDFPage(at: url, index: 0)
        let second = try await DocumentProcessor.shared.renderPDFPage(at: url, index: 1)
        let landscape = try XCTUnwrap(UIImage(data: first.original))
        let portrait = try XCTUnwrap(UIImage(data: second.original))
        XCTAssertGreaterThan(landscape.size.width, landscape.size.height)
        XCTAssertLessThan(portrait.size.width, portrait.size.height)
    }
    @MainActor func testNestedSectionsIncludeDescendantsAndRejectCyclesInTraversal() throws {
        let store = try container(); let context = store.mainContext
        let book = Notebook(title: "Physics"); context.insert(book)
        let chapter = BookSection(title: "Mechanics", rank: 0, book: book)
        let child = BookSection(title: "Energy", rank: 1, book: book); child.parentID = chapter.id
        context.insert(chapter); context.insert(child)
        let page = NotePage(imageData: Data([1]), thumbnailData: Data(), rank: 2, book: book); context.insert(page)
        book.applyOrder([.section(chapter), .section(child), .page(page)])
        XCTAssertEqual(book.depth(of: child), 1); XCTAssertEqual(book.pages(in: chapter).map(\.id), [page.id])
        chapter.parentID = child.id
        XCTAssertEqual(book.descendantIDs(of: chapter.id).count, 2)
        XCTAssertLessThanOrEqual(book.depth(of: child), 2)
    }
    @MainActor func testTrashAndMoveUndoKeepOriginalsAndHistory() throws {
        let store = try container(); let context = store.mainContext; let actions = LibraryActions()
        let book = Notebook(title: "Maths"); context.insert(book)
        let page = NotePage(imageData: Data([1, 2, 3]), thumbnailData: Data(), rank: 0)
        context.insert(page); try context.save()
        actions.move([page], to: book, before: nil, in: context)
        XCTAssertEqual(page.book?.id, book.id)
        actions.undo(); XCTAssertNil(page.book)
        actions.trash([page], in: context); XCTAssertNotNil(page.trashedAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotePage>()), 1)
        actions.undo(); XCTAssertNil(page.trashedAt); XCTAssertEqual(page.imageData, Data([1, 2, 3]))
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<PageRevision>()), 0)
    }
    @MainActor func testLinkStoresNoDuplicatePageOrImage() throws {
        let store = try container(); let context = store.mainContext
        let first = NotePage(imageData: Data([1]), thumbnailData: Data(), rank: 0)
        let second = NotePage(imageData: Data([2]), thumbnailData: Data(), rank: 1)
        context.insert(first); context.insert(second); context.insert(PageLink(source: first.id, target: second.id)); try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotePage>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PageLink>()), 1)
    }
    @MainActor func testCropAndRotationAreNonDestructive() async throws {
        let prepared = try await PageTemplates.shared.make("Graph")
        let store = try container(); let context = store.mainContext
        let page = NotePage(imageData: prepared.original, thumbnailData: prepared.thumbnail, rank: 0); context.insert(page)
        let actions = LibraryActions(); var edits = ImageAdjustments()
        edits.crop = NormalizedRect(x: 0.1, y: 0.2, width: 0.6, height: 0.4)
        edits.contrast = 1.4
        actions.edit([page], in: context, name: "Enhance") { page.enhancementData = edits.data }
        let snapshot = PageSnapshot(page)
        let renderedData = await PageImageRenderer.shared.render(snapshot)
        let rendered = try XCTUnwrap(renderedData)
        let image = try XCTUnwrap(UIImage(data: rendered))
        XCTAssertEqual(page.imageData, prepared.original)
        XCTAssertGreaterThan(image.size.width / image.size.height, 1)
        page.revisionCoverData = RecallCover.encode([RecallCover()])
        let oldRect = try XCTUnwrap(RecallCover.decode(page.revisionCoverData).first?.rect)
        actions.rotate([page], in: context)
        XCTAssertEqual(RecallCover.decode(page.revisionCoverData).first?.rect, oldRect.clockwise())
        XCTAssertEqual(page.imageData, prepared.original)
    }
    @MainActor func testWorkingFolderRestoresIntoFreshContainerAndProtectsIndex() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let oldBookmark = defaults.data(forKey: "workspaceBookmark"), oldName = defaults.string(forKey: "workspaceName")
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.set(oldBookmark, forKey: "workspaceBookmark"); defaults.set(oldName, forKey: "workspaceName")
        }
        let source = try container(); let context = source.mainContext
        let book = Notebook(title: "Portable maths"); book.spineLabel = "MATHS"; book.coverStyle = "gradient"; context.insert(book)
        let section = BookSection(title: "Algebra", rank: 0, book: book); context.insert(section)
        let page = NotePage(imageData: Data([5, 6, 7]), thumbnailData: Data(), rank: 1, book: book)
        page.text = "Portable recognised text"; page.drawingData = Data([8, 9]); page.isBookmarked = true
        page.sectionID = section.id; context.insert(page); context.insert(PageRevision(page: page, reason: "Saved")); try context.save()
        let workspace = WorkspaceFolder(); try await workspace.connect(directory, context: context)
        XCTAssertNil(workspace.error)
        let savedManifest = try await FolderArchive.shared.manifest(in: directory)
        let saved = try XCTUnwrap(savedManifest)
        let fresh = try container(); let reopened = WorkspaceFolder()
        try await reopened.connect(directory, context: fresh.mainContext)
        let restored = try XCTUnwrap(fresh.mainContext.fetch(FetchDescriptor<NotePage>()).first)
        XCTAssertEqual(restored.id, page.id); XCTAssertEqual(restored.imageData, page.imageData)
        XCTAssertEqual(restored.drawingData, page.drawingData); XCTAssertTrue(restored.isBookmarked)
        XCTAssertEqual(restored.text, page.text); XCTAssertEqual(restored.book?.spineLabel, "MATHS")
        XCTAssertEqual(restored.sectionID, section.id)
        let edits = LibraryActions()
        edits.edit([restored], in: fresh.mainContext, name: "Edit on another container") { restored.text = "Changed in the restored container" }
        await reopened.saveNow(context: fresh.mainContext)
        // A stale container must not overwrite an index saved by another container.
        await workspace.saveNow(context: context)
        XCTAssertNotNil(workspace.error)
        let latestManifest = try await FolderArchive.shared.manifest(in: directory)
        let latest = try XCTUnwrap(latestManifest)
        XCTAssertNotEqual(saved.savedAt, latest.savedAt)
        workspace.disconnect(); reopened.disconnect()
    }
    @MainActor func testLockedBooksStayOutOfPageAccess() throws {
        let store = try container(); let book = Notebook(title: "Private"); book.isLocked = true
        store.mainContext.insert(book)
        let page = NotePage(imageData: Data([1]), thumbnailData: Data(), rank: 0, book: book); store.mainContext.insert(page)
        let access = AccessController(); access.appUnlocked = true
        XCTAssertFalse(access.canRead(page)); access.unlockedBooks.insert(book.id); XCTAssertTrue(access.canRead(page))
        access.lock(); XCTAssertFalse(access.canRead(page))
    }
}
