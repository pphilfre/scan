import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

/// The entry point stays compact. The system camera/pickers provide capture;
/// destination selection happens only after the originals have been saved.
struct CaptureView: View {
    let importer: ImportCoordinator
    var initialBook: Notebook?
    var beforeEntryID: String?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var scanner = false
    @State private var files = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var batch: CapturedBatch?
    @State private var detent: PresentationDetent = .height(116)
    var body: some View {
        Group {
            if let batch {
                DestinationPicker(pages: batch.pages, isNewImport: true, initialBook: initialBook, initialBeforeID: beforeEntryID)
            } else {
                VStack(spacing: 12) {
                    if importer.isBusy { ImportProgress(importer: importer) }
                    else {
                        HStack(spacing: 42) {
                            Button { scanner = true } label: { Image(systemName: "camera").font(.title2).frame(width: 48, height: 48) }
                                .accessibilityLabel("Scan pages").accessibilityIdentifier("capture.scan")
                                .disabled(!VNDocumentCameraViewController.isSupported)
                            PhotosPicker(selection: $photos, maxSelectionCount: 100, matching: .images) {
                                Image(systemName: "photo.on.rectangle").font(.title2).frame(width: 48, height: 48)
                            }.accessibilityLabel("Import photos").accessibilityIdentifier("capture.photos")
                            Button { files = true } label: { Image(systemName: "folder").font(.title2).frame(width: 48, height: 48) }
                                .accessibilityLabel("Import PDFs or images").accessibilityIdentifier("capture.files")
                        }.buttonStyle(.plain)
                    }
                }.padding(20).accessibilityIdentifier("capture.toolbar")
            }
        }
        .presentationDetents(batch == nil ? [.height(116)] : [.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(importer.isBusy && batch == nil)
        .sheet(isPresented: $scanner) {
            ScannerView { images in
                importer.importScans(images, into: nil, context: context, completion: { captured($0) })
            } onError: { importer.error = $0 }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importer.importFiles(urls, into: nil, context: context, completion: { captured($0) })
            case .failure(let error): importer.error = error.localizedDescription
            }
        }
        #if DEBUG
        .task {
            if UITestFixture.enabled && ProcessInfo.processInfo.arguments.contains("-ui-test-import") {
                do { importer.importFiles([try UITestFixture.importURL()], into: nil, context: context, completion: { captured($0) }) }
                catch { importer.error = error.localizedDescription }
            }
        }
        #endif
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            importer.importPhotos(items, into: nil, context: context, completion: { captured($0) })
            photos = []
        }
        .onChange(of: importer.isBusy) { _, busy in
            if !busy && batch == nil && importer.error != nil { dismiss() }
        }
    }
    private func captured(_ pages: [NotePage]) {
        batch = CapturedBatch(pages: pages)
        detent = .medium
    }
}

struct CapturedBatch: Identifiable {
    let id = UUID()
    let pages: [NotePage]
}
