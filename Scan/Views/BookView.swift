import SwiftUI
import SwiftData

struct BookView: View {
    @Bindable var book: Notebook
    let importer: ImportCoordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var capture = false
    @State private var editBook = false
    @State private var newSection = false
    @State private var sectionTitle = ""
    @State private var editingSection: BookSection?
    @State private var selectedPage: NotePage?
    @State private var deleting = false
    @State private var share: ExportFile?
    @State private var exporting = false
    var body: some View {
        List {
            Section {
                HStack(alignment: .center, spacing: 24) {
                    BookCover(book: book).frame(width: 85)
                    VStack(alignment: .leading, spacing: 9) {
                        Text(book.title).font(.system(.title, design: .serif))
                        Text("\(book.pages?.count ?? 0) pages · \(book.sections?.count ?? 0) sections").font(.caption).foregroundStyle(.secondary)
                        Text("A little knowledge, collected.").font(.caption).foregroundStyle(.tertiary)
                    }
                }.padding(.vertical, 16)
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if book.entries.isEmpty {
                ContentUnavailableView("A fresh start", systemImage: "book.pages", description: Text("Scan or import your first page. Add dividers as your ideas grow."))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(book.entries) { entry in
                entryRow(entry)
                .draggable(entry.id)
                .dropDestination(for: String.self) { identifiers, _ in
                    guard let source = identifiers.first else { return false }
                    return drop(source, before: entry.id)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                var entries = book.entries
                entries.move(fromOffsets: source, toOffset: destination)
                book.applyOrder(entries)
                save()
                FolioStyle.haptic()
            }
        }
        .listStyle(.plain).background(FolioStyle.paper).scrollContentBackground(.hidden)
        .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit book", systemImage: "book.closed") { editBook = true }
                    Button("Add divider", systemImage: "rectangle.split.1x2") { sectionTitle = ""; editingSection = nil; newSection = true }
                    Button("Export PDF", systemImage: "square.and.arrow.up") { export() }.disabled(book.orderedPages.isEmpty || exporting)
                    Button("Delete book", systemImage: "trash", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if importer.isBusy { ImportProgress(importer: importer) }
                if exporting { ProgressView("Creating PDF…").font(.caption).padding().glassEffect() }
                Button { capture = true } label: { Label("Add pages", systemImage: "document.viewfinder").padding(.horizontal, 25).padding(.vertical, 8) }
                    .buttonStyle(.glassProminent).disabled(importer.isBusy)
            }.padding()
        }
        .sheet(isPresented: $capture) { CaptureView(books: [book], importer: importer, initialBook: book) }
        .sheet(isPresented: $editBook) { BookEditor(book: book) }
        .sheet(item: $share) { ShareSheet(items: [$0.url]) }
        .fullScreenCover(item: $selectedPage) { page in PageReader(pages: book.orderedPages, initialID: page.id, importer: importer) }
        .alert(editingSection == nil ? "New divider" : "Rename divider", isPresented: $newSection) {
            TextField("Section title", text: $sectionTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let title = sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return }
                if let editingSection { editingSection.title = title }
                else { context.insert(BookSection(title: title, rank: book.nextRank, book: book)) }
                saveOrder()
            }
        } message: { Text("Drag dividers and pages to organise your book.") }
        .confirmationDialog("Delete \(book.title) and all its pages?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete book", role: .destructive) {
                context.delete(book)
                do { try context.save(); dismiss() } catch { importer.error = error.localizedDescription }
            }
        }
    }
    @ViewBuilder private func entryRow(_ entry: BookEntry) -> some View {
        switch entry {
        case .section(let section):
            HStack(spacing: 12) {
                Image(systemName: "rectangle.split.1x2").foregroundStyle(FolioStyle.color(book.colorName))
                Text(section.title).font(.system(.headline, design: .serif))
                Rectangle().fill(FolioStyle.color(book.colorName).opacity(0.22)).frame(height: 1)
            }.padding(.vertical, 10)
            .contextMenu {
                Button("Rename", systemImage: "pencil") { sectionTitle = section.title; editingSection = section; newSection = true }
                Button("Remove divider", systemImage: "trash", role: .destructive) { context.delete(section); saveOrder() }
            }
        case .page(let page):
            Button { selectedPage = page } label: {
                PageRow(page: page, number: book.orderedPages.firstIndex(where: { $0.id == page.id }).map { $0 + 1 })
            }.buttonStyle(.plain)
            .contextMenu {
                Button(page.isFavourite ? "Remove favourite" : "Favourite", systemImage: page.isFavourite ? "star.slash" : "star") { page.isFavourite.toggle(); save() }
                Button("Duplicate", systemImage: "plus.square.on.square") { context.insert(page.copy(to: book)); saveOrder() }
                Button("Delete page", systemImage: "trash", role: .destructive) { context.delete(page); saveOrder() }
            }
        }
    }
    private func drop(_ source: String, before target: String) -> Bool {
        var entries = book.entries
        guard source != target, let sourceIndex = entries.firstIndex(where: { $0.id == source }) else { return false }
        let item = entries.remove(at: sourceIndex)
        guard let destination = entries.firstIndex(where: { $0.id == target }) else { return false }
        entries.insert(item, at: destination)
        book.applyOrder(entries); save(); FolioStyle.haptic()
        return true
    }
    private func saveOrder() { book.applyOrder(book.entries); save() }
    private func save() { do { try context.save() } catch { importer.error = error.localizedDescription } }
    private func export() {
        exporting = true
        let snapshots = book.orderedPages.map(PageSnapshot.init)
        let title = book.title
        Task {
            defer { exporting = false }
            do { share = ExportFile(url: try await PDFExporter.shared.export(snapshots, title: title)) }
            catch { importer.error = error.localizedDescription }
        }
    }
}

struct PageThumbnail: View {
    let page: NotePage
    var body: some View {
        ZStack {
            Color.white
            if let image = UIImage(data: page.thumbnailData) {
                Image(uiImage: image).resizable().scaledToFit().rotationEffect(.degrees(Double(page.rotation * 90)))
            } else { Image(systemName: "document").foregroundStyle(.secondary) }
        }.clipped().accessibilityHidden(true)
    }
}

struct PageRow: View {
    let page: NotePage
    var number: Int? = nil
    var query: String = ""
    var body: some View {
        HStack(spacing: 16) {
            PageThumbnail(page: page).frame(width: 56, height: 76).clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.12)) }
            VStack(alignment: .leading, spacing: 6) {
                HighlightedText(value: page.title, query: query).font(.subheadline.weight(.medium)).lineLimit(1)
                if !query.isEmpty {
                    HighlightedText(value: SmartMetadata.snippet(page.text, matching: query), query: query).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text(page.text.isEmpty ? recognitionLabel : page.text.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let number { Text("\(number.formatted(.number.precision(.integerLength(2))))").monospacedDigit() }
                    Text((page.detectedDate ?? page.createdAt).formatted(date: .abbreviated, time: .omitted))
                    if page.isFavourite { Image(systemName: "star.fill").foregroundStyle(.orange) }
                    if !page.tags.isEmpty { Text("#" + page.tags.joined(separator: " #")).lineLimit(1) }
                }.font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 7).contentShape(Rectangle())
    }
    private var recognitionLabel: String {
        switch page.recognitionState {
        case "pending", "recognising": "Recognising handwriting…"
        case "failed": "Original saved · retry text recognition"
        case "empty": "No text detected · original saved"
        default: "Add text to this page"
        }
    }
}
