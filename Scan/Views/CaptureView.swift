import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

struct CaptureView: View {
    let books: [Notebook]
    let importer: ImportCoordinator
    var initialBook: Notebook?
    var beforeEntryID: String?
    var autoScan = false
    @Environment(AccessController.self) private var access
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var bookID: UUID?
    @State private var scanner = false
    @State private var files = false
    @State private var photos: [PhotosPickerItem] = []
    private var destination: Notebook? { books.first { $0.id == bookID && $0.trashedAt == nil && access.canOpen($0) } }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "document.viewfinder").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(FolioStyle.ink).padding(.top, 25)
                Text("Let your notes\nturn a new page.").font(.system(.largeTitle, design: .serif))
                Text("Capture a page. Keep the original. Find every word.").font(.subheadline).foregroundStyle(.secondary)
                Picker("Save to", selection: $bookID) {
                    Text("Unfiled").tag(nil as UUID?)
                    ForEach(books.filter { $0.trashedAt == nil && access.canOpen($0) }) { Text($0.title).tag(Optional($0.id)) }
                }.padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
                Button { scanner = true } label: { CaptureOption(title: "Scan pages", subtitle: "Keep capturing, then tap Save", symbol: "camera") }
                    .disabled(!VNDocumentCameraViewController.isSupported)
                if !VNDocumentCameraViewController.isSupported {
                    Text("Scan on an iPhone or iPad, or import images here.").font(.caption).foregroundStyle(.secondary)
                }
                PhotosPicker(selection: $photos, maxSelectionCount: 100, matching: .images) {
                    CaptureOption(title: "Photos", subtitle: "Import one or more pages", symbol: "photo.on.rectangle")
                }
                Button { files = true } label: { CaptureOption(title: "Files", subtitle: "PDFs and images", symbol: "folder") }
                Spacer(minLength: 0)
                Label("Recognition happens on your device", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.buttonStyle(.plain).padding(28).background(FolioStyle.paper)
            .navigationTitle("Add pages").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { bookID = initialBook?.id }
            .task { if autoScan && VNDocumentCameraViewController.isSupported { scanner = true } }
            .sheet(isPresented: $scanner) {
                ScannerView { images in
                    importer.importScans(images, into: destination, before: beforeEntryID, context: context)
                    dismiss()
                } onError: { importer.error = $0 }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $files, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): importer.importFiles(urls, into: destination, before: beforeEntryID, context: context); dismiss()
                case .failure(let error): importer.error = error.localizedDescription
                }
            }
            .onChange(of: photos) { _, items in
                guard !items.isEmpty else { return }
                importer.importPhotos(items, into: destination, before: beforeEntryID, context: context)
                photos = []
                dismiss()
            }
        }.presentationDetents([.large])
    }
}

/// Value-only label: PhotosPicker evaluates its label outside the main actor.
struct CaptureOption: View {
    nonisolated let title: String
    nonisolated let subtitle: String
    nonisolated let symbol: String

    nonisolated init(title: String, subtitle: String, symbol: String) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.title2.weight(.light)).foregroundStyle(FolioStyle.ink).frame(width: 30)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(19).background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}
