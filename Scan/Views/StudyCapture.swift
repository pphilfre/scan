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
            ScrollView {
              VStack(alignment: .leading, spacing: 20) {
                Text("Bring your working in.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Capture every page in order. You’ll add marks and topics next.").foregroundStyle(.secondary)
                Button { scanner = true } label: {
                    VStack(spacing: 14) {
                        Image(systemName: "viewfinder").font(.system(size: 48, weight: .light))
                        Text("Scan pages").font(.title3.weight(.semibold))
                        Text("Keep adding pages, then tap Save").font(.subheadline)
                    }.frame(maxWidth: .infinity).padding(.vertical, 30)
                        .background(StudyPalette.focus.opacity(0.1), in: RoundedRectangle(cornerRadius: 28))
                }.buttonStyle(.plain).foregroundStyle(StudyPalette.focus).disabled(importer.isBusy || !VNDocumentCameraViewController.isSupported)
                if !VNDocumentCameraViewController.isSupported { Text("Camera scanning isn’t available here. Import photos or a PDF below.").font(.caption).foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    PhotosPicker(selection: $photos, maxSelectionCount: 100, selectionBehavior: .ordered, matching: .images) {
                        StudyActionTile(title: "Photos", detail: "Use selection order", symbol: "photo.on.rectangle", color: StudyPalette.focus)
                    }.buttonStyle(.plain).disabled(importer.isBusy)
                    Button { files = true } label: {
                        StudyActionTile(title: "Files", detail: "PDFs and images", symbol: "folder", color: StudyPalette.focus)
                    }.buttonStyle(.plain).disabled(importer.isBusy)
                }
                Button("Attach existing scans", systemImage: "link") { attachingExisting.toggle() }.buttonStyle(.bordered).disabled(importer.isBusy)
                if attachingExisting {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select pages in the intended order").font(.headline)
                        ForEach(pages.filter { access.canRead($0) }) { page in
                            Button {
                                if chosen.contains(page.id) { chosen.removeAll { $0 == page.id } } else { chosen.append(page.id) }
                            } label: {
                                HStack {
                                    PageThumbnail(page: page).frame(width: 36, height: 50).clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text(page.title).foregroundStyle(.primary); Spacer()
                                    if let index = chosen.firstIndex(of: page.id) { Text("\(index + 1)").monospacedDigit().foregroundStyle(StudyPalette.progress) }
                                    else { Image(systemName: "circle").foregroundStyle(.secondary) }
                                }.padding(12).background(StudyPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                        Button("Attach \(chosen.count) pages") { attach(chosen); chosen = []; attachingExisting = false }.disabled(chosen.isEmpty)
                    }
                }
                if importer.isBusy { ImportProgress(importer: importer) }
                if let message { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(StudyPalette.progress).accessibilityIdentifier("study.capture.result") }
              }.padding(22).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }.background(StudyPalette.canvas).navigationTitle("Paper scans").navigationBarTitleDisplayMode(.inline)
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
