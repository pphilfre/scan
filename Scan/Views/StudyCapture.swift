import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

/// Uses the existing original-first importer. The ordered UUID list is separate
/// from question metadata, notebook ranks, OCR, and annotation data.
struct StudyCaptureView: View {
    let recordID: String
    let importer: ImportCoordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \NotePage.rank) private var pages: [NotePage]
    @Environment(AccessController.self) private var access
    @State private var scanner = false
    @State private var files = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var attachingExisting = false
    @State private var chosen: [UUID] = []
    @State private var message: String?
    @State private var feedback = StudyFeedbackState()
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Pages are appended in capture or selection order. Your originals stay in Folio and use the same reader and annotation tools as your notes.").foregroundStyle(.secondary)
                    Button("Scan pages", systemImage: "camera") { scanner = true }.disabled(importer.isBusy || !VNDocumentCameraViewController.isSupported)
                    PhotosPicker(selection: $photos, maxSelectionCount: 100, selectionBehavior: .ordered, matching: .images) { Label("Import photos in selection order", systemImage: "photo.on.rectangle") }.disabled(importer.isBusy)
                    Button("Import PDF or image files", systemImage: "folder") { files = true }.disabled(importer.isBusy)
                    Button("Attach existing scans", systemImage: "link") { attachingExisting.toggle() }.disabled(importer.isBusy)
                }
                if attachingExisting {
                    Section("Select pages in the intended order") {
                        ForEach(pages.filter { access.canRead($0) }) { page in
                            Button {
                                if chosen.contains(page.id) { chosen.removeAll { $0 == page.id } } else { chosen.append(page.id) }
                            } label: {
                                HStack { Text(page.title); Spacer(); if let index = chosen.firstIndex(of: page.id) { Text("\(index + 1)").monospacedDigit() } }
                            }
                        }
                        Button("Attach \(chosen.count) pages") { attach(chosen); chosen = []; attachingExisting = false }.disabled(chosen.isEmpty)
                    }
                }
                if importer.isBusy { ImportProgress(importer: importer) }
                if let message { Text(message).accessibilityIdentifier("study.capture.result") }
            }.navigationTitle("Paper scans").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(importer.isBusy) } }
                .interactiveDismissDisabled(importer.isBusy)
                .sheet(isPresented: $scanner) {
                    ScannerView { images in
                        importer.importScans(images, into: nil, context: context) { attach($0.map(\.id)) }
                    } onError: { importer.error = $0 }
                }
                .fileImporter(isPresented: $files, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                    switch result {
                    case .success(let urls): importer.importFiles(urls, into: nil, context: context) { attach($0.map(\.id)) }
                    case .failure(let error): importer.error = error.localizedDescription
                    }
                }
                .onChange(of: photos) { _, selected in
                    guard !selected.isEmpty else { return }
                    importer.importPhotos(selected, into: nil, context: context) { attach($0.map(\.id)) }; photos = []
                }
                .alert("Capture needs attention", isPresented: Binding(get: { importer.error != nil }, set: { if !$0 { importer.error = nil } })) { Button("OK") {} } message: { Text(importer.error ?? "") }
                .onChange(of: importer.error) { _, value in if value != nil { feedback.error += 1 } }
                .studyFeedback(feedback)
        }
    }
    private func attach(_ ids: [UUID]) {
        do {
            guard var record = try StudyStore.records(context).first(where: { $0.id == recordID }) else {
                throw StudyFailure(issues: [.init(record: recordID, field: "pages", message: "The paper was removed. Your captured originals are safe in Unfiled.")])
            }
            var ordered = record.ids("pages")
            let before = ordered.count
            for id in ids where !ordered.contains(id) { ordered.append(id) }
            record.setIDs("pages", ordered)
            // A question range can be imported before its scans. Appending a
            // partial scan batch must not invalidate or remove those questions.
            try StudyStore.write([record], context: context)
            message = "\(ordered.count - before) pages attached · \(ordered.count) pages in total"
            feedback.success += 1
        } catch { importer.error = error.localizedDescription; feedback.error += 1 }
    }
}
