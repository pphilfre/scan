import XCTest
import SwiftData
import UIKit
import PencilKit
@testable import Folio

final class LibraryTests: XCTestCase {
    @MainActor private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Notebook.self, NotePage.self, BookSection.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
    @MainActor private func page(_ book: Notebook, rank: Double) -> NotePage {
        NotePage(imageData: Data([1, 2, 3]), thumbnailData: Data([4]), rank: rank, book: book)
    }
    @MainActor func testMovingDividerRegroupsAndRenumbersPages() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Notebook(title: "Maths")
        context.insert(book)
        let first = page(book, rank: 0)
        let divider = BookSection(title: "Algebra", rank: 1, book: book)
        let second = page(book, rank: 2)
        context.insert(first); context.insert(divider); context.insert(second)
        book.applyOrder([.page(first), .section(divider), .page(second)])
        XCTAssertNil(first.sectionID)
        XCTAssertEqual(second.sectionID, divider.id)
        book.applyOrder([.section(divider), .page(second), .page(first)])
        try context.save()
        XCTAssertEqual(book.orderedPages.map(\.id), [second.id, first.id])
        XCTAssertEqual(first.sectionID, divider.id)
        XCTAssertEqual(book.entries.map(\.rank), [0, 1, 2])
    }
    @MainActor func testDuplicatePreservesOriginalAndEditsIndependently() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let source = Notebook(title: "Maths"), destination = Notebook(title: "Revision")
        context.insert(source); context.insert(destination)
        let original = page(source, rank: 0)
        original.text = "Quadratic equations"
        original.tags = ["exam"]
        original.rotation = 1
        original.drawingData = PKDrawing().dataRepresentation()
        context.insert(original)
        let copy = original.copy(to: destination)
        context.insert(copy)
        try context.save()
        copy.text = "Edited copy"
        XCTAssertNotEqual(original.id, copy.id)
        XCTAssertEqual(original.text, "Quadratic equations")
        XCTAssertEqual(copy.imageData, original.imageData)
        XCTAssertEqual(copy.drawingData, original.drawingData)
        XCTAssertEqual(copy.rotation, 1)
        XCTAssertEqual(copy.book?.id, destination.id)
    }
    @MainActor func testCascadeRemovesOnlyDeletedBooksContent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = Notebook(title: "First"), second = Notebook(title: "Second")
        context.insert(first); context.insert(second)
        context.insert(page(first, rank: 0)); context.insert(page(second, rank: 0))
        context.insert(BookSection(title: "Divider", rank: 1, book: first))
        try context.save()
        context.delete(first)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotePage>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BookSection>()), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<NotePage>()).first?.book?.id, second.id)
    }
    @MainActor func testSmartMetadataAndSearchSnippet() {
        XCTAssertEqual(SmartMetadata.title(from: "\n  Quadratic equations\nExample one"), "Quadratic equations")
        XCTAssertEqual(SmartMetadata.title(from: "\n  "), "Untitled note")
        XCTAssertEqual(SmartMetadata.section(from: "Worked example: solve this equation"), "Worked examples")
        XCTAssertNotNil(SmartMetadata.date(from: "Lecture 15 October 2026"))
        let text = String(repeating: "Introduction ", count: 30) + "Elasticity of demand" + String(repeating: " notes", count: 40)
        let snippet = SmartMetadata.snippet(text, matching: "elasticity")
        XCTAssertTrue(snippet.contains("Elasticity"))
        XCTAssertLessThan(snippet.count, 200)
    }
    @MainActor func testVisionRecognisesClearTextAndRetainsSource() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1400, height: 700), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1400, height: 700))
            ("Physics lecture\nEnergy is conserved" as NSString).draw(at: CGPoint(x: 90, y: 110), withAttributes: [.font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor.black])
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.98))
        let prepared = try await DocumentProcessor.shared.prepare(data)
        XCTAssertEqual(prepared.original, data)
        XCTAssertFalse(prepared.thumbnail.isEmpty)
        let result = try await DocumentProcessor.shared.recognise(data, rotation: 0, vocabulary: ["Physics"])
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("Energy"), result.text)
        XCTAssertGreaterThan(result.confidence, 0.5)
    }
    @MainActor func testPDFExportAndImportRoundTrip() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
            ("Maths" as NSString).draw(at: CGPoint(x: 40, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 40)])
        }
        let container = try makeContainer()
        let book = Notebook(title: "Maths")
        container.mainContext.insert(book)
        let note = NotePage(imageData: try XCTUnwrap(image.jpegData(compressionQuality: 0.9)), thumbnailData: Data(), rank: 0, book: book)
        container.mainContext.insert(note)
        note.rotation = 1
        let url = try await PDFExporter.shared.export([PageSnapshot(note)], title: "Maths / Revision")
        defer { try? FileManager.default.removeItem(at: url) }
        let count = try await DocumentProcessor.shared.pdfPageCount(at: url)
        XCTAssertEqual(count, 1)
        let prepared = try await DocumentProcessor.shared.renderPDFPage(at: url, index: 0)
        let reimported = try XCTUnwrap(UIImage(data: prepared.original))
        XCTAssertGreaterThan(reimported.size.width, reimported.size.height)
    }
}
