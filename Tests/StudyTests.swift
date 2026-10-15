import XCTest
import SwiftData
@testable import Folio

final class StudyTests: XCTestCase {
    @MainActor private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Notebook.self, NotePage.self, BookSection.self, PageRevision.self, PageLink.self, StudyItem.self])
        let config: ModelConfiguration
        if let url { config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none) }
        return try ModelContainer(for: schema, configurations: [config])
    }
    private var example: [StudyRecord] { StudyInterchange.parse(StudyInterchange.example).records }

    func testExampleAndMultilineRoundTrip() throws {
        let parsed = StudyInterchange.parse(StudyInterchange.example)
        XCTAssertTrue(parsed.issues.isEmpty)
        XCTAssertEqual(parsed.records.count, 9)
        XCTAssertTrue(StudyRules.validate(parsed.records).isEmpty)
        let card = try XCTUnwrap(parsed.records.first { $0.type == .card })
        XCTAssertTrue(card["answer"].contains("\n"))
        let exported = try StudyInterchange.export(parsed.records)
        let restored = StudyInterchange.parse(exported)
        XCTAssertTrue(restored.issues.isEmpty)
        XCTAssertEqual(Set(restored.records.map(\.id)), Set(parsed.records.map(\.id)))
        XCTAssertEqual(restored.records.first { $0.id == card.id }, card)
    }
    func testParserReportsUnknownFieldsTypesAndWrongValueTypes() {
        let result = StudyInterchange.parse(#"{"format":"folio-study","version":1,"extra":"x","records":[{"type":"paper","id":"p","title":"Paper","year":2025,"secret":"x"},{"type":"invented","id":"bad"}]}"#)
        XCTAssertEqual(Set(result.issues.map(\.field)), ["extra", "year", "secret", "type"])
        XCTAssertFalse(StudyInterchange.parse("```json\n{}\n```").issues.isEmpty)
        XCTAssertFalse(StudyInterchange.parse(#"{"format":"folio-study","version":2,"records":[]}"#).issues.isEmpty)
        XCTAssertFalse(StudyInterchange.parse(#"{"format":"folio-study","version":true,"records":[]}"#).issues.isEmpty)
    }
    func testDuplicateIDsHaveSeparatePreviewRowsAndAnError() {
        let result = StudyInterchange.parse(#"{"format":"folio-study","version":1,"records":[{"type":"subject","id":"s","title":"First"},{"type":"subject","id":"s","title":"Second"}]}"#)
        XCTAssertTrue(result.issues.contains { $0.field == "id" })
        let rows = StudyInterchange.rows(result.records, existing: [])
        XCTAssertEqual(Set(rows.map(\.id)).count, 2)
        XCTAssertFalse(StudyInterchange.plan(rows, existing: []).issues.isEmpty)
    }
    func testValidationReportsRecordAndFieldAndRejectsCycles() {
        let subject = StudyRecord(.subject, id: "s", ["title": "Physics"])
        let a = StudyRecord(.topic, id: "a", ["title": "A", "subject": "s", "parent": "b"])
        let b = StudyRecord(.topic, id: "b", ["title": "B", "subject": "s", "parent": "a"])
        let paper = StudyRecord(.paper, id: "p", ["title": "Paper"])
        let question = StudyRecord(.question, id: "q", ["paper": "p", "label": "1(a)", "marks": "3", "earned": "4", "pageStart": "4", "pageEnd": "2", "topic": "missing"])
        let issues = StudyRules.validate([subject, a, b, paper, question])
        XCTAssertTrue(issues.contains { $0.record == "a" && $0.field == "parent" })
        XCTAssertTrue(issues.contains { $0.record == "q" && $0.field == "earned" })
        XCTAssertTrue(issues.contains { $0.record == "q" && $0.field == "pageEnd" })
        XCTAssertTrue(issues.contains { $0.record == "q" && $0.field == "topic" })
        XCTAssertFalse(StudyRules.validate([paper]).contains { $0.field == "subject" })
    }
    func testMarksUseLeafSubquestionsAndCountZeroAsMarked() {
        let parent = StudyRecord(.question, id: "q", ["marks": "99", "earned": "99"])
        let a = StudyRecord(.question, id: "a", ["parent": "q", "marks": "3", "earned": "0"])
        let b = StudyRecord(.question, id: "b", ["parent": "q", "marks": "2", "earned": "1.5"])
        let c = StudyRecord(.question, id: "c", ["marks": "4"])
        XCTAssertEqual(StudyMarks.total([parent, a, b, c]), StudyMarks(earned: 1.5, available: 9, marked: 2, count: 3))
        var corrected = b; corrected["earned"] = "2"
        XCTAssertEqual(StudyMarks.total([parent, a, corrected, c]).earned, 2)
    }
    func testSectionTotalsInheritParentsWithoutCountingThemTwice() {
        let parent = StudyRecord(.question, id: "q", ["section": "A", "marks": "10", "earned": "10"])
        let a = StudyRecord(.question, id: "a", ["parent": "q", "marks": "3", "earned": "2"])
        let b = StudyRecord(.question, id: "b", ["parent": "q", "section": "B", "marks": "4", "earned": "3"])
        let sections = StudyMarks.sections([parent, a, b])
        XCTAssertEqual(sections["A"]?.available, 3)
        XCTAssertEqual(sections["B"]?.available, 4)
        XCTAssertEqual(sections.values.reduce(0) { $0 + $1.earned }, StudyMarks.total([parent, a, b]).earned)
    }
    func testSubquestionsInheritScanRangesAndRetryIgnoresParentMarks() {
        let parent = StudyRecord(.question, id: "q", ["pageStart": "2", "pageEnd": "3", "marks": "10", "earned": "0"])
        let child = StudyRecord(.question, id: "a", ["parent": "q", "marks": "3", "earned": "3"])
        XCTAssertEqual(StudyRules.pageRange(child, in: [parent, child]), 2...3)
        XCTAssertFalse(StudyRules.needsRetry(parent, in: [parent, child]))
        var retry = child; retry["retryAt"] = "2026-10-16T17:00:00Z"
        XCTAssertTrue(StudyRules.needsRetry(parent, in: [parent, retry]))
    }
    func testSchedulingDoesNotPenaliseMissedDays() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var card = StudyRecord(.card, ["prompt": "Prompt", "answer": "Answer"])
        XCTAssertTrue(StudySchedule.due(card, now: now))
        card = StudySchedule.rate(card, "Got it", now: now)
        XCTAssertEqual(try XCTUnwrap(card.date("due")).timeIntervalSince(now), 3 * 86400, accuracy: 1)
        XCTAssertFalse(StudySchedule.due(card, now: now))
        XCTAssertTrue(StudySchedule.due(card, now: now.addingTimeInterval(20 * 86400)))
        let late = StudySchedule.rate(card, "Got it", now: now.addingTimeInterval(20 * 86400))
        XCTAssertEqual(late.number("interval") ?? 0, 6.9, accuracy: 0.001)
        let again = StudySchedule.rate(card, "Again", now: now)
        XCTAssertEqual(try XCTUnwrap(again.date("due")).timeIntervalSince(now), 600, accuracy: 1)
        XCTAssertEqual(StudySchedule.rate(card, "Nearly", now: now).number("interval"), 1)
        card["interval"] = "180"
        XCTAssertEqual(StudySchedule.rate(card, "Got it", now: now).number("interval"), 180)
    }
    func testRepeatedImportsSkipByDefaultAndUpdatesPreserveScanOrder() {
        let pages = [UUID(), UUID()]
        var paper = StudyRecord(.paper, id: "p", ["title": "Paper", "notes": "My annotations remain"])
        paper.setIDs("pages", pages)
        let imported = StudyRecord(.paper, id: "p", ["title": "Corrected title"])
        var rows = StudyInterchange.rows([imported], existing: [paper])
        XCTAssertEqual(rows[0].action, .skip)
        XCTAssertEqual(StudyInterchange.plan(rows, existing: [paper]).skipped, 1)
        rows[0].action = .update
        let plan = StudyInterchange.plan(rows, existing: [paper])
        XCTAssertTrue(plan.issues.isEmpty)
        XCTAssertEqual(plan.updates, 1)
        XCTAssertEqual(plan.records.first?.ids("pages"), pages)
        XCTAssertEqual(plan.records.first?["notes"], paper["notes"])
        rows[0].record.setIDs("pages", Array(pages.reversed()))
        XCTAssertEqual(StudyInterchange.plan(rows, existing: [paper]).records.first?.ids("pages"), pages)
    }
    func testImportDetectsLibraryChangesAfterPreview() {
        let subject = StudyRecord(.subject, id: "s", ["title": "Physics"])
        let newRows = StudyInterchange.rows([subject], existing: [])
        XCTAssertFalse(StudyInterchange.plan(newRows, existing: [subject]).issues.isEmpty)
        var updateRows = StudyInterchange.rows([subject], existing: [subject])
        updateRows[0].action = .update
        var changed = subject; changed["notes"] = "Added on another device"
        XCTAssertFalse(StudyInterchange.plan(updateRows, existing: [changed]).issues.isEmpty)
    }
    func testImportAsNewRemapsReferencesAndDestinations() throws {
        let existing = example
        var rows = StudyInterchange.rows(existing, existing: existing)
        for index in rows.indices { rows[index].action = .new }
        let plan = StudyInterchange.plan(rows, existing: existing)
        XCTAssertTrue(plan.issues.isEmpty, plan.issues.map(\.description).joined(separator: "\n"))
        XCTAssertEqual(plan.additions, existing.count)
        XCTAssertTrue(Set(plan.records.map(\.id)).isDisjoint(with: Set(existing.map(\.id))))
        let paper = try XCTUnwrap(plan.records.first { $0.type == .paper })
        let question = try XCTUnwrap(plan.records.first { $0.type == .question })
        XCTAssertEqual(question["paper"], paper.id)
        let source = try XCTUnwrap(plan.records.first { $0.type == .mistake })
        XCTAssertEqual(plan.records.first { $0.type == .card }?["source"], "record:" + source.id)
        let separate = StudyRecord(.question, id: "new-q", ["label": "2", "marks": "4"])
        let destination = StudyInterchange.plan(StudyInterchange.rows([separate], existing: existing), existing: existing, paper: "maths-2025-1")
        XCTAssertTrue(destination.issues.isEmpty)
        XCTAssertEqual(destination.records.first?["paper"], "maths-2025-1")
    }
    func testLikelyDuplicateDetectionCanonicalisesChangedParentIDs() {
        let existing = example
        var imported = existing
        let mapping = Dictionary(uniqueKeysWithValues: imported.map { ($0.id, "different-" + $0.id) })
        for index in imported.indices {
            let original = imported[index]
            imported[index].id = mapping[original.id]!
            for field in StudyRules.references(original.type).keys {
                if let id = mapping[original[field]] { imported[index][field] = id }
            }
        }
        let rows = StudyInterchange.rows(Array(imported.reversed()), existing: existing)
        XCTAssertTrue(rows.allSatisfy { $0.match != nil })
        XCTAssertEqual(StudyInterchange.plan(rows, existing: existing).skipped, existing.count)
    }
    @MainActor func testInvalidImportMakesNoPartialChanges() throws {
        let store = try container()
        let valid = StudyRecord(.subject, ["title": "Biology"])
        let invalid = StudyRecord(.card, ["prompt": "Missing answer"])
        XCTAssertThrowsError(try StudyStore.write([valid, invalid], context: store.mainContext))
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<StudyItem>()), 0)
    }
    @MainActor func testPreStudySchemaMigratesAdditively() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Before-study.store")
        try autoreleasepool {
            let schema = Schema([Notebook.self, NotePage.self, BookSection.self, PageRevision.self, PageLink.self])
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let book = Notebook(title: "Keep my notes"); old.mainContext.insert(book)
            let page = NotePage(imageData: Data([3, 4]), thumbnailData: Data(), rank: 0, book: book)
            page.text = "Before study tools"; page.drawingData = Data([5, 6]); old.mainContext.insert(page)
            try old.mainContext.save()
        }
        let current = try container(url: url)
        try StudyStore.write([StudyRecord(.paper, ["title": "First standalone paper"])], context: current.mainContext)
        let page = try XCTUnwrap(current.mainContext.fetch(FetchDescriptor<NotePage>()).first)
        XCTAssertEqual(page.book?.title, "Keep my notes"); XCTAssertEqual(page.imageData, Data([3, 4]))
        XCTAssertEqual(page.drawingData, Data([5, 6])); XCTAssertEqual(page.text, "Before study tools")
    }
    func testPreStudyStoreIsBackedUpBeforeMigration() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard, oldFormat = UserDefaults.standard.object(forKey: "folioStoreFormat")
        defer { defaults.set(oldFormat, forKey: "folioStoreFormat"); try? FileManager.default.removeItem(at: directory) }
        let store = directory.appending(path: "Folio.store"), wal = directory.appending(path: "Folio.store-wal")
        try Data([1, 2]).write(to: store); try Data([3, 4]).write(to: wal)
        defaults.set(3, forKey: "folioStoreFormat")
        try StorageMigration.prepareStore(at: store)
        let backups = try FileManager.default.contentsOfDirectory(at: directory.appending(path: "Library Backups"), includingPropertiesForKeys: nil)
        let backup = try XCTUnwrap(backups.first { $0.lastPathComponent.hasPrefix("Before-v4-") })
        XCTAssertEqual(try Data(contentsOf: backup.appending(path: "Folio.store")), Data([1, 2]))
        XCTAssertEqual(try Data(contentsOf: backup.appending(path: "Folio.store-wal")), Data([3, 4]))
        XCTAssertEqual(try Data(contentsOf: store), Data([1, 2]))
    }
    func testPreviousFolderManifestDecodesWithoutStudyData() throws {
        var legacy = FolderManifest(books: [], sections: [], pages: [], pageRecords: [:], revisions: [], links: [])
        legacy.format = 2
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(FolderManifest.self, from: data)
        XCTAssertEqual(decoded.format, 2); XCTAssertNil(decoded.study)
    }
    @MainActor func testPersistenceKeepsMarksHistoryAndImmutableOriginals() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Study.store")
        let pageID = UUID()
        try autoreleasepool {
            let store = try container(url: url); let context = store.mainContext
            let page = NotePage(imageData: Data([7, 8, 9]), thumbnailData: Data(), rank: 42)
            page.id = pageID; page.drawingData = Data([1, 2]); context.insert(page)
            var paper = StudyRecord(.paper, id: "p", ["title": "Standalone paper"]); paper.setIDs("pages", [page.id])
            let question = StudyRecord(.question, id: "q", ["paper": "p", "label": "1(a)", "marks": "3", "earned": "1", "pageStart": "1"])
            try StudyStore.write([paper, question], context: context)
            var changed = question; changed["earned"] = "3"
            try StudyStore.write(StudyStore.attempt(question, replacing: changed), context: context)
            XCTAssertEqual(page.rank, 42); XCTAssertEqual(page.imageData, Data([7, 8, 9])); XCTAssertEqual(page.drawingData, Data([1, 2]))
        }
        let reopened = try container(url: url)
        let records = try StudyStore.records(reopened.mainContext)
        XCTAssertEqual(records.first { $0.id == "q" }?["earned"], "3")
        XCTAssertEqual(records.first { $0.id == "p" }?.ids("pages"), [pageID])
        XCTAssertEqual(records.filter { $0.type == .attempt }.count, 1)
        let item = try XCTUnwrap(StudyStore.items(reopened.mainContext).first { $0.id == "q" })
        XCTAssertEqual(try item.snapshot().history.first?.record["earned"], "1")
    }
    @MainActor func testConcurrentMergeRetainsLosingEditAndTombstoneWinsTie() throws {
        let store = try container(); let context = store.mainContext
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let original = StudyRecord(.card, id: "c", ["prompt": "P", "answer": "Original"])
        try StudyStore.write([original], context: context)
        let item = try XCTUnwrap(StudyStore.items(context).first); item.modifiedAt = date
        var changed = original; changed["answer"] = "Concurrent answer"
        try StudyStore.merge([StudySnapshot(record: changed, modified: date.addingTimeInterval(1), history: [])], context: context)
        XCTAssertEqual(try item.decoded()["answer"], "Concurrent answer")
        XCTAssertTrue(try item.snapshot().history.contains { $0.record == original })
        let snapshot = try item.snapshot()
        try StudyStore.merge([StudySnapshot(record: changed, modified: snapshot.modified, removed: date, history: [])], context: context)
        XCTAssertNotNil(item.removedAt)
        try StudyStore.merge([snapshot], context: context)
        XCTAssertNotNil(item.removedAt, "An equal-time live snapshot must not resurrect a deletion")
    }
    @MainActor func testConcurrentPaperAppendsKeepBothScanBatches() throws {
        let store = try container(); let context = store.mainContext
        let ids = [UUID(), UUID(), UUID()]
        var paper = StudyRecord(.paper, id: "p", ["title": "Paper"])
        paper.setIDs("pages", [ids[0], ids[1]])
        try StudyStore.write([paper], context: context)
        let item = try XCTUnwrap(StudyStore.items(context).first)
        var other = paper; other.setIDs("pages", [ids[0], ids[2]])
        let incoming = StudySnapshot(record: other, modified: item.modifiedAt.addingTimeInterval(1), history: [])
        try StudyStore.merge([incoming], context: context)
        XCTAssertEqual(try item.decoded().ids("pages"), [ids[0], ids[2], ids[1]])
        try StudyStore.merge([incoming], context: context)
        XCTAssertEqual(try item.decoded().ids("pages").count, 3)
    }
    @MainActor func testReconcilerConsolidatesCloudDuplicatesAndPreservesBothEdits() throws {
        let store = try container(); let context = store.mainContext
        let a = StudyRecord(.card, id: "same", ["prompt": "P", "answer": "A"])
        let b = StudyRecord(.card, id: "same", ["prompt": "P", "answer": "B"])
        let first = try StudyItem(a), second = try StudyItem(b)
        second.modifiedAt = first.modifiedAt
        context.insert(first); context.insert(second); try context.save()
        try LibraryReconciler.run(context)
        let remaining = try StudyStore.items(context)
        XCTAssertEqual(remaining.count, 1)
        let snapshot = try XCTUnwrap(remaining.first).snapshot()
        XCTAssertEqual(Set(([snapshot.record] + snapshot.history.map(\.record)).map { $0["answer"] }), ["A", "B"])
    }
    @MainActor func testDeletingReviewedCardIsPossibleAndDoesNotBreakExport() throws {
        let store = try container(); let context = store.mainContext
        let card = StudyRecord(.card, id: "c", ["prompt": "Prompt", "answer": "Answer"])
        let review = StudyRecord(.review, ["card": "c", "rating": "Got it", "date": "2026-10-15T17:00:00Z"])
        try StudyStore.write([card, review], context: context)
        try StudyStore.remove(card, context: context)
        XCTAssertTrue(try StudyStore.records(context).isEmpty)
        XCTAssertEqual(try StudyStore.items(context).count, 2, "Tombstones and history stay available for folder merge")
        XCTAssertNoThrow(try StudyInterchange.export(StudyStore.records(context)))
    }
    @MainActor func testFolderRoundTripIncludesStudyDataHistoryAndDeletion() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let bookmark = defaults.data(forKey: "workspaceBookmark"), name = defaults.string(forKey: "workspaceName")
        let workspace = WorkspaceFolder(), restoredWorkspace = WorkspaceFolder()
        defer {
            workspace.disconnect(); restoredWorkspace.disconnect()
            defaults.set(bookmark, forKey: "workspaceBookmark"); defaults.set(name, forKey: "workspaceName")
            try? FileManager.default.removeItem(at: directory)
        }
        let source = try container()
        try StudyStore.write(example, context: source.mainContext)
        try await workspace.connect(directory, context: source.mainContext)
        let card = try XCTUnwrap(example.first { $0.type == .card })
        try StudyStore.write([StudySchedule.rate(card, "Nearly")], context: source.mainContext)
        try StudyStore.remove(card, context: source.mainContext)
        var savedManifest: FolderManifest?
        for _ in 0..<200 {
            savedManifest = try await FolderArchive.shared.manifest(in: directory)
            if savedManifest?.study?.first(where: { $0.record.id == card.id })?.removed != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNil(workspace.error)
        let manifest = try XCTUnwrap(savedManifest)
        XCTAssertNotNil(manifest.study?.first { $0.record.id == card.id }?.removed, "Study saves must automatically reach the working folder, including while sheets are open")
        XCTAssertEqual(manifest.format, 3)
        XCTAssertEqual(manifest.study?.count, example.count)
        workspace.disconnect()
        let restored = try container()
        try await restoredWorkspace.connect(directory, context: restored.mainContext)
        let snapshots = try StudyStore.items(restored.mainContext).map { try $0.snapshot() }
        XCTAssertEqual(snapshots.count, example.count)
        XCTAssertNotNil(snapshots.first { $0.record.id == card.id }?.removed)
        XCTAssertEqual(snapshots.first { $0.record.id == card.id }?.history.count, 1)
        XCTAssertEqual(try StudyStore.records(restored.mainContext).filter { $0.type == .paper }.count, 1)
    }
    func testTopicWorkspaceIncludesNestedQuestionsAndMistakeCards() {
        let records = example
        let scope = records.first { $0.id == "algebra" }
        let scoped = StudyRules.scoped(records, to: scope)
        XCTAssertTrue(scoped.contains { $0.id == "quadratics" })
        XCTAssertTrue(scoped.contains { $0.id == "q1a" })
        XCTAssertTrue(scoped.contains { $0.id == "missed-root" })
        XCTAssertTrue(scoped.contains { $0.id == "roots-card" })
    }
}
