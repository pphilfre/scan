import SwiftUI
import SwiftData

struct PageReader: View {
    let pages: [NotePage]
    let initialID: UUID
    let importer: ImportCoordinator
    var searchTerm: String = ""
    var bookEntries: [BookEntry] = []
    var initialEntryID: String?
    var preservePageOrder = false
    var titleOverride: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AccessController.self) private var access
    @Environment(LibraryActions.self) private var actions
    @AppStorage("showPageNumbers") private var showNumbers = true
    @AppStorage("showThumbnails") private var showThumbnails = true
    @AppStorage("pageCurl") private var pageCurl = true
    @AppStorage("readerFullscreen") private var defaultFullscreen = false
    @AppStorage("readingPaper") private var paper = "system"
    @State private var currentID: String?
    @State private var textMode = false
    @State private var editing = false
    @State private var draftTitle = ""
    @State private var draftText = ""
    @State private var draftTags = ""
    @State private var draftSectionID: UUID?
    @State private var fullScreen = false
    @State private var tool: ReaderTool?
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var rerunOCR = false
    @State private var share: ExportFile?
    @State private var exporting = false
    @State private var studyDraft: StudyDraft?
    private var livePages: [NotePage] { pages.filter { !$0.isDeleted && $0.trashedAt == nil && $0.book?.trashedAt == nil } }
    private var liveEntries: [BookEntry] {
        let source: [BookEntry]
        if preservePageOrder { source = livePages.map(BookEntry.page) }
        else if !bookEntries.isEmpty { source = bookEntries.sorted { $0.rank == $1.rank ? $0.id < $1.id : $0.rank < $1.rank } }
        else if let book = livePages.first?.book,
                Set(livePages.map(\.id)) == Set(book.orderedPages.map(\.id)) { source = book.entries }
        else { source = livePages.map(BookEntry.page) }
        return source.filter { entry in
            switch entry {
            case .page(let page): return livePages.contains { $0.id == page.id }
            case .section(let section): return !section.isDeleted && section.trashedAt == nil && section.book?.trashedAt == nil
            }
        }
    }
    private var currentEntry: BookEntry? { liveEntries.first { $0.id == (currentID ?? initialEntryID ?? "page:" + initialID.uuidString) } ?? liveEntries.first }
    private var current: NotePage? { if case .some(.page(let page)) = currentEntry { return page }; return nil }
    private var currentBook: Notebook? {
        switch currentEntry {
        case .some(.page(let page)): page.book
        case .some(.section(let section)): section.book
        case nil: nil
        }
    }
    private var readerTitle: String {
        if let titleOverride { return titleOverride }
        switch currentEntry {
        case .some(.page(let page)): return page.book?.title ?? "Unfiled"
        case .some(.section(let section)): return section.title
        case nil: return "Unfiled"
        }
    }
    private var index: Int { liveEntries.firstIndex { $0.id == currentEntry?.id } ?? 0 }
    private var canReadCurrent: Bool {
        switch currentEntry {
        case .some(.page(let page)): access.canRead(page)
        case .some(.section(let section)): section.book.map(access.canOpen) ?? false
        case nil: false
        }
    }
    private var selectedPages: [NotePage] { livePages.filter { selection.contains($0.id) && access.canRead($0) } }
    var body: some View {
        NavigationStack {
            Group {
                if let entry = currentEntry {
                    switch entry {
                    case .page(let page):
                        if access.canRead(page) { readingContent(page) }
                        else if let book = page.book { BookLockView(book: book) }
                        else { LibraryLockView() }
                    case .section(let section):
                        if canReadCurrent { imageContent }
                        else if let book = section.book { BookLockView(book: book) }
                        else { LibraryLockView() }
                    }
                } else { ContentUnavailableView("Page moved to Recently Deleted", systemImage: "trash") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(fullScreen ? "" : readerTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar(fullScreen ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if editing { Button("Cancel") { editing = false } }
                    else { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
                }
                if let page = current, access.canRead(page) {
                    ToolbarItem(placement: .principal) {
                        Picker("View", selection: $textMode) { Image(systemName: "document").tag(false); Image(systemName: "text.alignleft").tag(true) }
                            .pickerStyle(.segmented).frame(width: 112).accessibilityLabel("Original scan or recognised text").disabled(editing)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if editing {
                            Button("Save") { saveEdits(page) }.fontWeight(.semibold)
                                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            Button("Edit page", systemImage: "pencil") { beginEditing(page) }.labelStyle(.iconOnly)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) { pageMenu(page) }
                }
            }
            .safeAreaInset(edge: .bottom) { if !fullScreen, !editing, canReadCurrent { bottomControls } }
            .overlay(alignment: .topTrailing) {
                if fullScreen {
                    Button { withAnimation(.smooth) { fullScreen = false } } label: { Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 44, height: 44) }
                        .glassEffect(in: .circle).padding().accessibilityLabel("Exit full screen")
                }
            }
            .sheet(item: $tool) { item in toolSheet(item) }
            .sheet(item: $share) { ShareSheet(items: [$0.url]) }
            .sheet(item: $studyDraft) { StudyEditor(record: $0.record) }
            .confirmationDialog("Replace recognised text? Your current text stays in version history.", isPresented: $rerunOCR, titleVisibility: .visible) {
                Button("Recognise again") { if let page = current, access.canRead(page) { Task { await importer.recognise(page, context: context) } } }
            }
            .onAppear { currentID = initialEntryID ?? "page:" + initialID.uuidString; fullScreen = defaultFullscreen; markViewed() }
            .onChange(of: currentID) { _, _ in editing = false; markViewed() }
            .modifier(ActionError())
        }
    }
    @ViewBuilder private func readingContent(_ page: NotePage) -> some View {
        if textMode {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if editing {
                        TextField("Page title", text: $draftTitle).font(.system(.title, design: .serif))
                        TextField("Tags, separated by commas", text: $draftTags).textInputAutocapitalization(.never)
                        if let book = page.book {
                            Picker("Divider", selection: $draftSectionID) {
                                Text("Before first divider").tag(nil as UUID?)
                                ForEach(book.activeSections) { section in Text(section.title).tag(Optional(section.id)) }
                            }
                        }
                    } else { Text(page.title).font(.system(.title, design: .serif)) }
                    if ["pending", "recognising"].contains(page.recognitionState) { ProgressView("Recognising…") }
                    if editing { TextEditor(text: $draftText).frame(minHeight: 350).accessibilityLabel("Recognised text") }
                    else if page.text.isEmpty { ContentUnavailableView("No text recognised", systemImage: "text.viewfinder", description: Text("Edit text or try recognition again from the page menu.")) }
                    else { HighlightedText(value: page.text, query: searchTerm).font(.body).lineSpacing(7).textSelection(.enabled) }
                }.padding(26).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
            }.background(readingColor).accessibilityIdentifier("reader.text")
        } else { imageContent }
    }
    private var imageContent: some View {
        NativePageTurner(entries: liveEntries, currentID: Binding(get: { currentEntry?.id ?? "page:" + initialID.uuidString }, set: { currentID = $0 }), reduceMotion: reduceMotion || !pageCurl, paper: paper)
            .id("\(reduceMotion)-\(pageCurl)").ignoresSafeArea(edges: fullScreen ? .all : [])
            .safeAreaInset(edge: .trailing, spacing: 0) {
                if !fullScreen, let book = currentBook, !book.activeSections.isEmpty {
                    SectionTabs(book: book) { section in currentID = "section:" + section.id.uuidString }
                }
            }
    }
    private var readingColor: Color { paper == "warm" ? Color(red: 0.94, green: 0.91, blue: 0.84) : paper == "dark" ? Color(white: 0.1) : Color(uiColor: .secondarySystemGroupedBackground) }
    private func pageMenu(_ page: NotePage) -> some View {
        Menu {
            Button(selecting ? "Done selecting" : "Select pages", systemImage: "checkmark.circle") { selecting.toggle(); selection = [page.id] }
            Button("Annotate", systemImage: "pencil.tip.crop.circle") { open(.ink) }
            Button("Crop & enhance", systemImage: "slider.horizontal.3") { open(.enhance) }
            Button("Revision mode", systemImage: "rectangle.on.rectangle") { open(.revision) }
            Button("Make flashcard", systemImage: "rectangle.stack.badge.plus") {
                studyDraft = StudyDraft(record: StudyRecord(.card, ["prompt": page.title, "answer": page.text, "sourcePage": page.id.uuidString, "source": "Note: " + page.title]))
            }
            Button(page.isBookmarked ? "Remove bookmark" : "Bookmark", systemImage: "bookmark") { actions.edit([page], in: context, name: "Bookmark") { page.isBookmarked.toggle() } }
            Button(page.isFavourite ? "Remove favourite" : "Favourite", systemImage: "star") { actions.edit([page], in: context, name: "Favourite") { page.isFavourite.toggle() } }
            Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") { withAnimation(.smooth) { fullScreen = true; textMode = false } }
            ControlGroup {
                Button("Rotate", systemImage: "rotate.right") { actions.rotate([page], in: context) }
                Button("Duplicate", systemImage: "plus.square.on.square") { actions.duplicate([page], in: context) }
                Button("Move", systemImage: "folder") { open(.move) }
            }
            Button("Related pages", systemImage: "link") { open(.links) }
            Button("Insert paper after", systemImage: "document.badge.plus") { open(.paper) }
            Button("Version history", systemImage: "clock.arrow.circlepath") { open(.history) }
            Button("Recognise again", systemImage: "text.viewfinder") { rerunOCR = true }.disabled(page.recognitionState == "recognising")
            Button("Export PDF", systemImage: "square.and.arrow.up") { export([page]) }.disabled(exporting)
            if actions.undoTitle != nil { Button("Undo", systemImage: "arrow.uturn.backward") { actions.undo() } }
            Button("Delete page", systemImage: "trash", role: .destructive) { actions.trash([page], in: context) }
        } label: { Image(systemName: "ellipsis") }.accessibilityIdentifier("reader.menu")
    }
    @ViewBuilder private func toolSheet(_ item: ReaderTool) -> some View {
        Group {
            switch item.kind {
            case .ink: AnnotationEditor(page: item.page, importer: importer)
            case .enhance: EnhancementEditor(pages: [item.page])
            case .revision: RevisionMode(page: item.page)
            case .move: DestinationPicker(pages: [item.page])
            case .links: PageLinksView(page: item.page, importer: importer)
            case .history: PageHistoryView(page: item.page)
            case .paper: TemplatePicker(book: item.page.book, beforeEntryID: insertionAfter(item.page))
            }
        }.modifier(PageProtection(page: item.page))
    }
    private var bottomControls: some View {
        VStack(spacing: 10) {
            if exporting { ProgressView("Exporting…").font(.caption) }
            if showThumbnails || selecting {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(Array(liveEntries.enumerated()), id: \.element.id) { offset, entry in
                                Button {
                                    if selecting, case .page(let page) = entry {
                                        if !selection.insert(page.id).inserted { selection.remove(page.id) }
                                    } else { currentID = entry.id }
                                } label: {
                                    VStack(spacing: 4) {
                                        Group {
                                            switch entry {
                                            case .page(let page): PageThumbnail(page: page)
                                            case .section(let section): Image(systemName: section.symbol).foregroundStyle(FolioStyle.color(section.colorName))
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .background(FolioStyle.color(section.colorName).opacity(0.15))
                                            }
                                        }.frame(width: 38, height: 50).clipShape(RoundedRectangle(cornerRadius: 3))
                                            .overlay { RoundedRectangle(cornerRadius: 3).stroke(currentEntry?.id == entry.id ? FolioStyle.ink : .clear, lineWidth: 2) }
                                        if selecting, case .page(let page) = entry { Image(systemName: selection.contains(page.id) ? "checkmark.circle.fill" : "circle").font(.caption) }
                                        else if showNumbers { Text("\(offset + 1)").font(.system(size: 9)).foregroundStyle(.secondary) }
                                    }
                                }.buttonStyle(.plain).id(entry.id).accessibilityIdentifier("reader.thumbnail.\(offset)").accessibilityLabel("\(offset + 1), \(entry.title)")
                            }
                        }.padding(.horizontal, 16).padding(.top, 4)
                    }
                    .frame(height: 76).accessibilityIdentifier("reader.thumbnails")
                    .onChange(of: currentID) { _, id in withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) } }
                    .onAppear { proxy.scrollTo(initialEntryID ?? "page:" + initialID.uuidString, anchor: .center) }
                }
            }
            if selecting {
                HStack {
                    Button("Done") { selecting = false; selection = [] }
                    Spacer()
                    Button(selection.count == livePages.count ? "Deselect all" : "Select all") {
                        selection = selection.count == livePages.count ? [] : Set(livePages.filter(access.canRead).map(\.id))
                    }
                    Spacer()
                    Button("Share \(selectedPages.count)", systemImage: "square.and.arrow.up") { export(selectedPages) }
                        .disabled(selectedPages.isEmpty || exporting).accessibilityIdentifier("reader.exportSelection")
                }.font(.subheadline).padding(.horizontal, 16)
            } else {
                HStack {
                    Button("Previous page", systemImage: "chevron.left") { navigate(-1) }.labelStyle(.iconOnly).disabled(index == 0)
                    Spacer()
                    if showNumbers { Text("\(index + 1) of \(liveEntries.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Next page", systemImage: "chevron.right") { navigate(1) }.labelStyle(.iconOnly).disabled(index >= liveEntries.count - 1)
                }.padding(.horizontal, 20)
            }
        }.padding(.vertical, 10).glassEffect(in: .rect(cornerRadius: 22)).padding(.horizontal, 12).padding(.bottom, 5)
    }
    private func insertionAfter(_ page: NotePage) -> String? {
        guard let entries = page.book?.entries, let position = entries.firstIndex(where: { $0.id == "page:" + page.id.uuidString }), entries.indices.contains(position + 1) else { return nil }
        return entries[position + 1].id
    }
    private func open(_ kind: ReaderTool.Kind) { if let page = current { tool = ReaderTool(kind: kind, page: page) } }
    private func navigate(_ delta: Int) { guard liveEntries.indices.contains(index + delta) else { return }; currentID = liveEntries[index + delta].id; FolioStyle.haptic() }
    private func beginEditing(_ page: NotePage) {
        draftTitle = page.title; draftText = page.text; draftTags = page.tags.joined(separator: ", "); draftSectionID = page.sectionID
        textMode = true; editing = true
    }
    private func saveEdits(_ page: NotePage) {
        guard access.canRead(page) else { return }
        actions.edit([page], in: context, name: "Edit page") {
            page.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            page.text = draftText
            page.tags = Array(Set(draftTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
            if page.sectionID != draftSectionID, let book = page.book {
                var entries = book.entries.filter { $0.id != "page:" + page.id.uuidString }
                let position = draftSectionID.flatMap { id in entries.firstIndex { $0.id == "section:" + id.uuidString }.map { $0 + 1 } } ?? 0
                entries.insert(.page(page), at: position)
                book.applyOrder(entries)
            }
        }
        editing = false
    }
    private func markViewed() { guard let page = current, access.canRead(page) else { return }; page.lastViewedAt = .now; do { try LibraryPersistence.save(context) } catch { actions.error = error.localizedDescription } }
    private func export(_ pages: [NotePage]) {
        guard !pages.isEmpty, pages.allSatisfy(access.canRead) else { return }
        exporting = true; let pageIDs = pages.map(\.id)
        let title = pages.count == 1 ? pages[0].title : (current?.book?.title ?? "Selected notes")
        Task {
            defer { exporting = false }
            do { share = ExportFile(url: try await PDFExporter.shared.export(pageIDs: pageIDs, container: context.container, title: title)) }
            catch { actions.error = error.localizedDescription }
        }
    }
}

/// A sheet carries both its action and page, so the first presentation cannot
/// observe an unset action or a different page after a swipe.
struct ReaderTool: Identifiable {
    enum Kind: String, CaseIterable { case ink, enhance, revision, move, links, history, paper }
    let id = UUID()
    let kind: Kind
    let page: NotePage
}
