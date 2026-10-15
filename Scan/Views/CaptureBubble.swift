import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

/// Opens capture sources in place. Only the native scanner/pickers and the
/// destination prompt are presented after a source is chosen.
struct CaptureBubble: View {
    let importer: ImportCoordinator
    var book: Notebook?
    var beforeEntryID: String?
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var scanner = false
    @State private var files = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var batch: CapturedBatch?

    var body: some View {
        VStack(spacing: 10) {
            if expanded {
                HStack(spacing: 14) {
                    sourceButton("Scan", icon: "camera", id: "capture.scan") { scanner = true }
                        .disabled(!VNDocumentCameraViewController.isSupported)
                    PhotosPicker(selection: $photos, maxSelectionCount: 100, matching: .images) {
                        sourceLabel("Photos", icon: "photo.on.rectangle")
                    }.buttonStyle(.plain).accessibilityIdentifier("capture.photos")
                    sourceButton("Files", icon: "folder", id: "capture.files") { files = true }
                }
                .transition(reduceMotion ? .opacity : .scale(scale: 0.55, anchor: .bottom).combined(with: .opacity))
            }
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.72)) { expanded.toggle() }
                FolioStyle.haptic()
                #if DEBUG
                if UITestFixture.enabled && ProcessInfo.processInfo.arguments.contains("-ui-test-import") {
                    do { importer.importFiles([try UITestFixture.importURL()], into: nil, context: context, completion: { captured($0) }) }
                    catch { importer.error = error.localizedDescription }
                }
                #endif
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .rotationEffect(.degrees(expanded ? 45 : 0))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(.glassProminent)
            .disabled(importer.isBusy)
            .accessibilityLabel(expanded ? "Close capture actions" : "Add pages")
            .accessibilityIdentifier("library.addPages")
        }
        .accessibilityIdentifier("capture.bubble")
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
        .sheet(item: $batch) { result in
            DestinationPicker(pages: result.pages, isNewImport: true, initialBook: book, initialBeforeID: beforeEntryID)
        }
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            importer.importPhotos(items, into: nil, context: context, completion: { captured($0) })
            photos = []
        }
    }

    private func sourceButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { sourceLabel(title, icon: icon) }
            .buttonStyle(.plain).accessibilityIdentifier(id)
    }
    private func sourceLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption2.weight(.medium))
        }
        .frame(width: 64, height: 62)
        .glassEffect(in: .rect(cornerRadius: 20))
        .accessibilityLabel(title)
    }
    private func captured(_ pages: [NotePage]) {
        expanded = false
        batch = CapturedBatch(pages: pages)
    }
}
