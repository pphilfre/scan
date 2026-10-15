import SwiftUI
import SwiftData

struct PageOrganiser: View {
    var book: Notebook?
    let importer: ImportCoordinator
    @Query(sort: \NotePage.rank) private var allPages: [NotePage]
    @Query(sort: \Notebook.createdAt) private var allBooks: [Notebook]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryActions.self) private var actions
    @Environment(AccessController.self) private var access
    @AppStorage("thumbnailWidth") private var thumbnailWidth = 105.0
    @AppStorage("pageLayout") private var layout = "grid"
    @State private var selection: Set<UUID> = []
    @State private var moving = false
    @State private var renaming = false
    @State private var tagging = false
    @State private var enhancing = false
    @State private var capture = false
    @State private var template = false
    @State private var prefix = ""
    @State private var tags = ""
    @State private var deleting = false
    @State private var share: ExportFile?
    @State private var exporting = false
    @State private var reader: NotePage?
    private var pages: [NotePage] { book?.orderedPages ?? allPages.filter { $0.book == nil && $0.trashedAt == nil }.sorted { $0.rank < $1.rank } }
    private var selected: [NotePage] { pages.filter { selection.contains($0.id) } }
    private var allowed: Bool { book.map(access.canOpen) ?? true }
    var body: some View {
        Group {
            if let book, !allowed { BookLockView(book: book) }
            else { content }
        }
        .navigationTitle(book == nil ? "Unfiled" : "Organise").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            if allowed {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(selection.count == pages.count ? "Deselect all" : "Select all", systemImage: "checkmark.circle") { selection = selection.count == pages.count ? [] : Set(pages.map(\.id)) }
                        Button("Add scans", systemImage: "document.viewfinder") { capture = true }.disabled(importer.isBusy)
                        Button("Paper template", systemImage: "document.badge.plus") { template = true }
                        if actions.undoTitle != nil { Button("Undo", systemImage: "arrow.uturn.backward") { actions.undo() } }
                        Picker("Layout", selection: $layout) { Text("Grid").tag("grid"); Text("List").tag("list") }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { if allowed { bottomBar } }
        .sheet(isPresented: $moving) { DestinationPicker(pages: selected) }
        .sheet(isPresented: $enhancing) { EnhancementEditor(pages: selected) }
        .sheet(isPresented: $capture) { CaptureView(books: allBooks.filter { $0.trashedAt == nil }, importer: importer, initialBook: book) }
        .sheet(isPresented: $template) { TemplatePicker(book: book) }
        .sheet(item: $share) { ShareSheet(items: [$0.url]) }
        .fullScreenCover(item: $reader) { page in PageReader(pages: pages, initialID: page.id, importer: importer) }
        .alert("Rename \(selected.count) pages", isPresented: $renaming) {
            TextField("Title prefix", text: $prefix)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let clean = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty, allowed else { return }
                actions.edit(selected, in: context, name: "Rename pages") {
                    for (index, page) in selected.enumerated() { page.title = selected.count == 1 ? clean : "\(clean) \(index + 1)" }
                }
            }
        }
        .alert("Add tags", isPresented: $tagging) {
            TextField("Revision, Homework, Important…", text: $tags)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let added = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                guard allowed else { return }
                actions.edit(selected, in: context, name: "Tag pages") { for page in selected { page.tags = Array(Set(page.tags + added)).sorted() } }
            }
        }
        .confirmationDialog("Move \(selected.count) pages to Recently Deleted?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete pages", role: .destructive) { if allowed { actions.trash(selected, in: context); selection = [] } }
        }
        .modifier(ActionError())
    }
    @ViewBuilder private var content: some View {
        if pages.isEmpty {
            ContentUnavailableView(book == nil ? "All filed away" : "No pages yet", systemImage: "tray", description: Text("Scan pages now and organise them when you’re ready."))
        } else if layout == "list" {
            List {
                ForEach(pages) { page in selectable(page, grid: false) }
                .onMove { indices, offset in
                    var ordered = pages; ordered.move(fromOffsets: indices, toOffset: offset)
                    reorder(ordered)
                }
            }.listStyle(.plain)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailWidth, maximum: thumbnailWidth + 70), spacing: 16)], spacing: 20) {
                    ForEach(pages) { page in selectable(page, grid: true) }
                    Color.clear.frame(height: 60).dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first else { return false }; return drop(id, before: nil)
                    }
                }.padding(20)
            }.background(FolioStyle.paper)
        }
    }
    private func selectable(_ page: NotePage, grid: Bool) -> some View {
        Button {
            if selection.contains(page.id) { selection.remove(page.id) } else { selection.insert(page.id) }
            FolioStyle.haptic()
        } label: {
            HStack(spacing: 12) {
                if !grid { Image(systemName: selection.contains(page.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selection.contains(page.id) ? FolioStyle.ink : .secondary) }
                if grid {
                    VStack(alignment: .leading, spacing: 7) {
                        PageThumbnail(page: page).aspectRatio(0.72, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .topTrailing) { Image(systemName: selection.contains(page.id) ? "checkmark.circle.fill" : "circle").symbolRenderingMode(.palette).foregroundStyle(selection.contains(page.id) ? FolioStyle.ink : .gray, .white).font(.title3).padding(7) }
                        Text(page.title).font(.caption).lineLimit(1)
                    }
                } else { PageRow(page: page) }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityAddTraits(selection.contains(page.id) ? .isSelected : [])
        .draggable("page:" + page.id.uuidString)
        .dropDestination(for: String.self) { ids, _ in guard let id = ids.first else { return false }; return drop(id, before: page.id) }
        .contextMenu { Button("Read page", systemImage: "book") { reader = page } }
    }
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if importer.isBusy { ImportProgress(importer: importer).padding(.horizontal) }
            UndoBanner()
            HStack {
                Text("\(selection.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if exporting { ProgressView() }
                Menu {
                    Button("Rename", systemImage: "pencil") { prefix = ""; renaming = true }
                    Button("Tags", systemImage: "tag") { tags = ""; tagging = true }
                    Button("Duplicate", systemImage: "plus.square.on.square") { actions.duplicate(selected, in: context) }
                    Button("Rotate", systemImage: "rotate.right") { actions.rotate(selected, in: context) }
                    Button("Crop & enhance", systemImage: "slider.horizontal.3") { enhancing = true }
                    Button("Move", systemImage: "folder") { moving = true }
                    Button("Export PDF", systemImage: "square.and.arrow.up") { export() }.disabled(exporting)
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }
                } label: { Label("Actions", systemImage: "ellipsis.circle") }.disabled(selected.isEmpty)
            }.padding(.horizontal, 22).padding(.vertical, 14).background(.bar)
        }
    }
    private func drop(_ id: String, before target: UUID?) -> Bool {
        guard allowed, let source = pages.first(where: { "page:" + $0.id.uuidString == id }) else { return false }
        if let book { actions.reorder(id, before: target.map { "page:" + $0.uuidString }, in: book, context: context) }
        else {
            var ordered = pages.filter { $0.id != source.id }
            let position = target.flatMap { id in ordered.firstIndex { $0.id == id } } ?? ordered.count
            ordered.insert(source, at: position); reorder(ordered)
        }
        return true
    }
    private func reorder(_ ordered: [NotePage]) {
        actions.edit(ordered, in: context, name: "Reorder pages") {
            if let book {
                // Keep dividers at their positions while replacing page slots.
                var index = 0
                let entries = book.entries.map { entry -> BookEntry in
                    if case .page = entry { defer { index += 1 }; return .page(ordered[index]) }
                    return entry
                }
                book.applyOrder(entries)
            } else { for (index, page) in ordered.enumerated() { page.rank = Double(index) } }
        }
    }
    private func export() {
        guard allowed else { return }
        exporting = true; let pageIDs = selected.map(\.id)
        Task {
            defer { exporting = false }
            do { share = ExportFile(url: try await PDFExporter.shared.export(pageIDs: pageIDs, container: context.container, title: book?.title ?? "Unfiled")) }
            catch { actions.error = error.localizedDescription }
        }
    }
}

struct DestinationPicker: View {
    let pages: [NotePage]
    @Query(sort: \Notebook.createdAt) private var books: [Notebook]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryActions.self) private var actions
    @Environment(AccessController.self) private var access
    @State private var bookID: UUID?
    @State private var beforeID: String?
    private var destination: Notebook? { books.first { $0.id == bookID && $0.trashedAt == nil && access.canOpen($0) } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    Picker("Book", selection: $bookID) {
                        Text("Unfiled").tag(nil as UUID?)
                        ForEach(books.filter { $0.trashedAt == nil && access.canOpen($0) }) { Text($0.title).tag(Optional($0.id)) }
                    }
                    if let destination {
                        Picker("Insert before", selection: $beforeID) {
                            Text("End of book").tag(nil as String?)
                            ForEach(destination.entries.filter { entry in !pages.contains { "page:" + $0.id.uuidString == entry.id } }) { entry in
                                Text(entry.title).tag(Optional(entry.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move \(pages.count) pages").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        guard pages.allSatisfy(access.canRead), bookID == nil || destination != nil else { return }
                        actions.move(pages, to: destination, before: beforeID, in: context); dismiss()
                    }
                }
            }
            .onChange(of: bookID) { _, _ in beforeID = nil }
        }
    }
}

struct TemplatePicker: View {
    var book: Notebook?
    var beforeEntryID: String?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryActions.self) private var actions
    @Environment(AccessController.self) private var access
    @State private var busy = false
    var body: some View {
        NavigationStack {
            List(PageTemplates.styles, id: \.self) { style in
                Button { add(style) } label: { Label(style, systemImage: style == "Blank" ? "document" : style == "Dotted" ? "circle.grid.3x3" : "square.grid.3x3") }.disabled(busy)
            }
            .overlay { if busy { ProgressView().padding().glassEffect() } }
            .navigationTitle("Paper").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.presentationDetents([.medium])
    }
    private func add(_ style: String) {
        guard book.map(access.canOpen) ?? true else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let prepared = try await PageTemplates.shared.make(style)
                guard book?.isDeleted != true, book?.trashedAt == nil, book.map(access.canOpen) ?? true else { return }
                let page = NotePage(imageData: prepared.original, thumbnailData: prepared.thumbnail, rank: book?.nextRank ?? Date.now.timeIntervalSince1970, book: book)
                page.title = style + " paper"; page.recognitionState = "complete"
                context.insert(page)
                if let book { LibraryActions.place(page, in: book, before: beforeEntryID) }
                try context.save()
                actions.register("Add paper") { page.trashedAt = .now; try context.save() }
                dismiss()
            } catch { actions.error = error.localizedDescription }
        }
    }
}
