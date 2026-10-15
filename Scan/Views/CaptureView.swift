import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

struct CaptureView: View {
    let books: [Notebook]
    let importer: ImportCoordinator
    var initialBook: Notebook?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var bookID: UUID?
    @State private var scanner = false
    @State private var files = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var newBook = false
    private var destination: Notebook? { books.first { $0.id == bookID } ?? initialBook ?? books.first }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "document.viewfinder").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(FolioStyle.ink).padding(.top, 25)
                Text("Let your notes\nturn a new page.").font(.system(.largeTitle, design: .serif))
                Text("Capture a page. Keep the original. Find every word.").font(.subheadline).foregroundStyle(.secondary)
                if books.isEmpty {
                    Button("Create your first book", systemImage: "plus") { newBook = true }.buttonStyle(.glassProminent)
                } else {
                    Picker("Save to", selection: $bookID) { ForEach(books) { Text($0.title).tag(Optional($0.id)) } }
                        .padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
                    Button { scanner = true } label: { CaptureOption(title: "Scan pages", subtitle: "Auto crop, straighten and enhance", symbol: "camera") }
                        .disabled(!VNDocumentCameraViewController.isSupported || destination == nil)
                    if !VNDocumentCameraViewController.isSupported {
                        Text("Document scanning needs a supported iPhone or iPad. You can import photos or PDFs here.").font(.caption).foregroundStyle(.secondary)
                    }
                    PhotosPicker(selection: $photos, maxSelectionCount: 50, matching: .images) { CaptureOption(title: "Import photos", subtitle: "Handwriting, whiteboards and loose pages", symbol: "photo.on.rectangle") }
                    Button { files = true } label: { CaptureOption(title: "Import files", subtitle: "PDFs and images from Files", symbol: "folder") }
                }
                Spacer(minLength: 0)
                Label("Recognition happens on your device", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.buttonStyle(.plain).padding(28).background(FolioStyle.paper)
            .navigationTitle("Add pages").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { bookID = (initialBook ?? books.first)?.id }
            .sheet(isPresented: $scanner) {
                ScannerView { images in
                    guard let destination else { return }
                    importer.importScans(images, into: destination, context: context)
                    dismiss()
                } onError: { importer.error = $0 }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $newBook) { BookEditor() }
            .fileImporter(isPresented: $files, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                guard let destination else { return }
                switch result {
                case .success(let urls): importer.importFiles(urls, into: destination, context: context); dismiss()
                case .failure(let error): importer.error = error.localizedDescription
                }
            }
            .onChange(of: photos) { _, items in
                guard !items.isEmpty, let destination else { return }
                importer.importPhotos(items, into: destination, context: context)
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
