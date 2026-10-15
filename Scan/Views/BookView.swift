import SwiftUI
import SwiftData

struct BookView: View {
    @Bindable var book: Notebook
    let importer: ImportCoordinator
    var initialSectionID: UUID?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AccessController.self) private var access
    @Environment(LibraryActions.self) private var actions
    @AppStorage("pageLayout") private var layout = "grid"
    @AppStorage("thumbnailWidth") private var thumbnailWidth = 105.0
    @AppStorage("showPageNumbers") private var showNumbers = true
    @State private var bookSheet: BookSheet?
    @State private var editBook = false
    @State private var organiser = false
    @State private var selectedPage: NotePage?
    @State private var deleting = false
    @State private var share: ExportFile?
    @State private var exporting = false
    @State private var exportSections = false
    @State private var filter = "all"
    @State private var jumpID: String?
    private var visiblePages: [NotePage] {
        switch filter {
        case "bookmarks": book.orderedPages.filter(\.isBookmarked)
        case "recent": book.orderedPages.filter { $0.lastViewedAt != nil }.sorted { ($0.lastViewedAt ?? .distantPast) > ($1.lastViewedAt ?? .distantPast) }
        default: book.orderedPages
        }
    }
    var body: some View {
        Group {
            if !access.canOpen(book) { BookLockView(book: book) }
            else { contents }
        }
        .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { if access.canOpen(book) { toolbar } }
        .sheet(item: $bookSheet) { item in
            switch item.kind {
            case .capture: CaptureView(importer: importer, initialBook: book, beforeEntryID: item.before)
            case .paper: TemplatePicker(book: book, beforeEntryID: item.before)
            case .divider: SectionEditor(book: book, section: item.section, initialParent: item.parent)
            }
        }
        .sheet(isPresented: $exportSections) { SectionExportPicker(book: book) }
        .sheet(isPresented: $editBook) { BookEditor(book: book) }
        .sheet(isPresented: $organiser) { NavigationStack { PageOrganiser(book: book, importer: importer) } }
        .sheet(item: $share) { ShareSheet(items: [$0.url]) }
        .fullScreenCover(item: $selectedPage) { page in PageReader(pages: book.orderedPages, initialID: page.id, importer: importer) }
        .confirmationDialog("Move this book to Recently Deleted?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete book", role: .destructive) { actions.trashBook(book, context: context); dismiss() }
        }
        .modifier(ActionError())
    }
    private var contents: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("Pages", selection: $filter) {
                        Text("All").tag("all"); Text("Bookmarks").tag("bookmarks"); Text("Recent").tag("recent")
                    }.pickerStyle(.segmented)
                    if visiblePages.isEmpty && book.activeSections.isEmpty {
                        ContentUnavailableView("No pages yet", systemImage: "book.pages", description: Text("Scan a note or add a paper template."))
                    }
                    if filter == "all" {
                        pageGroup(book.orderedPages.filter { $0.sectionID == nil })
                        ForEach(book.activeSections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                divider(section).id("section:" + section.id.uuidString)
                                pageGroup(book.orderedPages.filter { $0.sectionID == section.id })
                            }
                        }
                    } else { pageGroup(visiblePages) }
                    Color.clear.frame(height: 24).dropDestination(for: String.self) { items, _ in
                        guard let source = items.first else { return false }
                        actions.reorder(source, before: nil, in: book, context: context); return true
                    }
                }.padding(20).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }.background(FolioStyle.paper)
            .safeAreaInset(edge: .trailing, spacing: 0) {
                if !book.activeSections.isEmpty && filter == "all" {
                    SectionTabs(book: book) { section in withAnimation(.smooth) { proxy.scrollTo("section:" + section.id.uuidString, anchor: .top) } }
                }
            }
            .onAppear { if let initialSectionID { jumpID = "section:" + initialSectionID.uuidString } }
            .onChange(of: jumpID) { _, id in withAnimation(.smooth) { proxy.scrollTo(id, anchor: .top) } }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if importer.isBusy { ImportProgress(importer: importer).padding(.horizontal) }
                if exporting { ProgressView("Exporting…").font(.caption) }
                UndoBanner()
            }.padding(.bottom, 6)
        }
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Paper template", systemImage: "document.badge.plus") { bookSheet = BookSheet(kind: .paper) }
                Button("Organise pages", systemImage: "square.grid.2x2") { organiser = true }
                Button("Export sections…", systemImage: "square.and.arrow.up.on.square") { exportSections = true }.disabled(book.activeSections.isEmpty)
                Button("Customise book", systemImage: "paintpalette") { editBook = true }
                Button("Add divider", systemImage: "rectangle.split.1x2") { bookSheet = BookSheet(kind: .divider) }
                Button("Export book", systemImage: "square.and.arrow.up") { export(book.orderedPages, title: book.title) }.disabled(book.orderedPages.isEmpty || exporting)
                Button(book.isLocked ? "Remove book lock" : "Protect book", systemImage: "lock") { toggleLock() }
                if actions.undoTitle != nil { Button("Undo", systemImage: "arrow.uturn.backward") { actions.undo() } }
                Button("Delete book", systemImage: "trash", role: .destructive) { deleting = true }
            } label: { Image(systemName: "ellipsis") }
        }
        ToolbarItem(placement: .bottomBar) {
            Button { bookSheet = BookSheet(kind: .capture) } label: {
                Label("Add page", systemImage: "plus").padding(.horizontal, 18).padding(.vertical, 5)
            }.buttonStyle(.glassProminent).disabled(importer.isBusy)
        }
    }
    @ViewBuilder private func pageGroup(_ pages: [NotePage]) -> some View {
        if layout == "list" {
            LazyVStack(spacing: 8) { ForEach(pages) { page in cell(page, grid: false) } }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailWidth, maximum: thumbnailWidth + 60), spacing: 16)], spacing: 20) {
                ForEach(pages) { page in cell(page, grid: true) }
            }
        }
    }
    private func cell(_ page: NotePage, grid: Bool) -> some View {
        Button { selectedPage = page } label: {
            Group {
                if grid {
                    VStack(alignment: .leading, spacing: 7) {
                        PageThumbnail(page: page).aspectRatio(0.72, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 5)).shadow(color: .black.opacity(0.06), radius: 3, y: 2)
                        HStack(spacing: 4) {
                            if showNumbers { Text("\((book.orderedPages.firstIndex { $0.id == page.id } ?? 0) + 1)").foregroundStyle(.secondary) }
                            Text(page.title).lineLimit(1)
                            if page.isBookmarked { Image(systemName: "bookmark.fill").foregroundStyle(FolioStyle.ink) }
                        }.font(.caption2)
                    }
                } else { PageRow(page: page, number: showNumbers ? book.orderedPages.firstIndex(where: { $0.id == page.id }).map { $0 + 1 } : nil) }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("book.page." + page.title)
        .draggable("page:" + page.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let source = items.first else { return false }
            actions.reorder(source, before: "page:" + page.id.uuidString, in: book, context: context); return true
        }
        .contextMenu {
            Button("Insert before", systemImage: "plus") { bookSheet = BookSheet(kind: .capture, before: "page:" + page.id.uuidString) }
            Button("Insert paper before", systemImage: "document.badge.plus") { bookSheet = BookSheet(kind: .paper, before: "page:" + page.id.uuidString) }
            Button(page.isBookmarked ? "Remove bookmark" : "Bookmark", systemImage: "bookmark") { actions.edit([page], in: context, name: "Bookmark") { page.isBookmarked.toggle() } }
            Button("Duplicate", systemImage: "plus.square.on.square") { actions.duplicate([page], in: context) }
            Button("Rotate", systemImage: "rotate.right") { actions.rotate([page], in: context) }
            Button("Delete", systemImage: "trash", role: .destructive) { actions.trash([page], in: context) }
        }
    }
    private func divider(_ section: BookSection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: section.symbol)
            Text(section.title).font(.system(.headline, design: .serif))
            Spacer()
            Text("\(book.pages(in: section).count)").font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(FolioStyle.color(section.colorName))
        .padding(.leading, CGFloat(book.depth(of: section) * 14)).padding(12)
        .background(section.dividerStyle == "band" ? FolioStyle.color(section.colorName).opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottom) { if section.dividerStyle != "band" { Rectangle().fill(FolioStyle.color(section.colorName).opacity(0.3)).frame(height: section.dividerStyle == "minimal" ? 1 : 3) } }
        .draggable("section:" + section.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let source = items.first else { return false }
            actions.reorder(source, before: "section:" + section.id.uuidString, in: book, context: context); return true
        }
        .contextMenu {
            Button("Edit divider", systemImage: "pencil") { bookSheet = BookSheet(kind: .divider, section: section) }
            Button("Add subsection", systemImage: "rectangle.stack.badge.plus") { bookSheet = BookSheet(kind: .divider, parent: section.id) }
            Button("Insert pages here", systemImage: "plus") {
                let items = book.entries; let index = items.firstIndex { $0.id == "section:" + section.id.uuidString } ?? items.count - 1
                bookSheet = BookSheet(kind: .capture, before: items.indices.contains(index + 1) ? items[index + 1].id : nil)
            }
            Button("Export section", systemImage: "square.and.arrow.up") { export(book.pages(in: section), title: section.title) }.disabled(book.pages(in: section).isEmpty)
            Button("Remove divider", systemImage: "trash", role: .destructive) { actions.removeSection(section, context: context) }
        }
    }
    private func toggleLock() {
        Task {
            if await access.authenticate(reason: "Change protection for \(book.title)") {
                book.modifiedAt = .now; book.isLocked.toggle(); if book.isLocked { access.unlockedBooks.insert(book.id) }
                do { try LibraryPersistence.save(context) } catch { actions.error = error.localizedDescription }
            }
        }
    }
    private func export(_ pages: [NotePage], title: String) {
        guard access.canOpen(book) else { return }
        exporting = true
        let pageIDs = pages.map(\.id)
        Task {
            defer { exporting = false }
            do { share = ExportFile(url: try await PDFExporter.shared.export(pageIDs: pageIDs, container: context.container, title: title)) }
            catch { actions.error = error.localizedDescription }
        }
    }
}

private struct BookSheet: Identifiable {
    enum Kind { case capture, paper, divider }
    let id = UUID()
    let kind: Kind
    var before: String?
    var section: BookSection?
    var parent: UUID?
}
