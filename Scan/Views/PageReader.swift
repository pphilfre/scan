import SwiftUI
import SwiftData

struct PageReader: View {
    let pages: [NotePage]
    let initialID: UUID
    let importer: ImportCoordinator
    var searchTerm: String = ""
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
    @State private var currentID: UUID?
    @State private var textMode = false
    @State private var fullScreen = false
    @State private var tool: String?
    @State private var sheet = false
    @State private var rerunOCR = false
    @State private var share: ExportFile?
    @State private var exporting = false
    private var livePages: [NotePage] { pages.filter { !$0.isDeleted && $0.trashedAt == nil && $0.book?.trashedAt == nil } }
    private var current: NotePage? { livePages.first { $0.id == (currentID ?? initialID) } ?? livePages.first }
    private var index: Int { livePages.firstIndex { $0.id == current?.id } ?? 0 }
    var body: some View {
        NavigationStack {
            Group {
                if let page = current {
                    if access.canRead(page) { readingContent(page) }
                    else if let book = page.book { BookLockView(book: book) }
                    else { LibraryLockView() }
                } else { ContentUnavailableView("Page moved to Recently Deleted", systemImage: "trash") }
            }
            .navigationTitle(fullScreen ? "" : (current?.book?.title ?? "Unfiled")).navigationBarTitleDisplayMode(.inline)
            .toolbar(fullScreen ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
                if let page = current, access.canRead(page) {
                    ToolbarItem(placement: .principal) {
                        Picker("View", selection: $textMode) { Image(systemName: "document").tag(false); Image(systemName: "text.alignleft").tag(true) }
                            .pickerStyle(.segmented).frame(width: 112).accessibilityLabel("Original scan or recognised text")
                    }
                    ToolbarItem(placement: .topBarTrailing) { pageMenu(page) }
                }
            }
            .safeAreaInset(edge: .bottom) { if !fullScreen, let page = current, access.canRead(page) { bottomControls } }
            .overlay(alignment: .topTrailing) {
                if fullScreen {
                    Button { withAnimation(.smooth) { fullScreen = false } } label: { Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 44, height: 44) }
                        .glassEffect(in: .circle).padding().accessibilityLabel("Exit full screen")
                }
            }
            .sheet(isPresented: $sheet) { if let page = current { toolSheet(page) } }
            .sheet(item: $share) { ShareSheet(items: [$0.url]) }
            .confirmationDialog("Replace recognised text? Your current text stays in version history.", isPresented: $rerunOCR, titleVisibility: .visible) {
                Button("Recognise again") { if let page = current, access.canRead(page) { Task { await importer.recognise(page, context: context) } } }
            }
            .onAppear { currentID = initialID; fullScreen = defaultFullscreen; markViewed() }
            .onChange(of: currentID) { _, _ in markViewed() }
            .modifier(ActionError())
        }
    }
    @ViewBuilder private func readingContent(_ page: NotePage) -> some View {
        if textMode {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(page.title).font(.system(.title, design: .serif))
                    if ["pending", "recognising"].contains(page.recognitionState) { ProgressView("Recognising…") }
                    else if page.text.isEmpty { ContentUnavailableView("No text recognised", systemImage: "text.viewfinder", description: Text("Edit text or try recognition again from the page menu.")) }
                    else { HighlightedText(value: page.text, query: searchTerm).font(.body).lineSpacing(7).textSelection(.enabled) }
                }.padding(26).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
            }.background(readingColor)
        } else {
            NativePageTurner(pages: livePages, currentID: Binding(get: { current?.id ?? initialID }, set: { currentID = $0 }), reduceMotion: reduceMotion || !pageCurl, paper: paper)
                .id("\(reduceMotion)-\(pageCurl)").ignoresSafeArea(edges: fullScreen ? .all : [])
                .safeAreaInset(edge: .trailing, spacing: 0) {
                    if !fullScreen, let book = page.book, !book.activeSections.isEmpty {
                        SectionTabs(book: book) { section in if let target = book.pages(in: section).first { currentID = target.id } }
                    }
                }
        }
    }
    private var readingColor: Color { paper == "warm" ? Color(red: 0.94, green: 0.91, blue: 0.84) : paper == "dark" ? Color(white: 0.1) : Color(uiColor: .secondarySystemGroupedBackground) }
    private func pageMenu(_ page: NotePage) -> some View {
        Menu {
            Button("Edit details & text", systemImage: "pencil") { open("details") }
            Button("Annotate", systemImage: "pencil.tip.crop.circle") { open("ink") }
            Button("Crop & enhance", systemImage: "slider.horizontal.3") { open("enhance") }
            Button("Revision mode", systemImage: "rectangle.on.rectangle") { open("revision") }
            Button(page.isBookmarked ? "Remove bookmark" : "Bookmark", systemImage: "bookmark") { actions.edit([page], in: context, name: "Bookmark") { page.isBookmarked.toggle() } }
            Button(page.isFavourite ? "Remove favourite" : "Favourite", systemImage: "star") { actions.edit([page], in: context, name: "Favourite") { page.isFavourite.toggle() } }
            Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") { withAnimation(.smooth) { fullScreen = true; textMode = false } }
            ControlGroup {
                Button("Rotate", systemImage: "rotate.right") { actions.rotate([page], in: context) }
                Button("Duplicate", systemImage: "plus.square.on.square") { actions.duplicate([page], in: context) }
                Button("Move", systemImage: "folder") { open("move") }
            }
            Button("Related pages", systemImage: "link") { open("links") }
            Button("Insert paper after", systemImage: "document.badge.plus") { open("paper") }
            Button("Version history", systemImage: "clock.arrow.circlepath") { open("history") }
            Button("Recognise again", systemImage: "text.viewfinder") { rerunOCR = true }.disabled(page.recognitionState == "recognising")
            Button("Export PDF", systemImage: "square.and.arrow.up") { export(page) }.disabled(exporting)
            if actions.undoTitle != nil { Button("Undo", systemImage: "arrow.uturn.backward") { actions.undo() } }
            Button("Delete page", systemImage: "trash", role: .destructive) { actions.trash([page], in: context) }
        } label: { Image(systemName: "ellipsis") }
    }
    @ViewBuilder private func toolSheet(_ page: NotePage) -> some View {
        Group {
            switch tool {
            case "details": PageDetailsView(page: page, importer: importer)
            case "ink": AnnotationEditor(page: page, importer: importer)
            case "enhance": EnhancementEditor(pages: [page])
            case "revision": RevisionMode(page: page)
            case "move": DestinationPicker(pages: [page])
            case "links": PageLinksView(page: page, importer: importer)
            case "history": PageHistoryView(page: page)
            case "paper": TemplatePicker(book: page.book, beforeEntryID: insertionAfter(page))
            default: EmptyView()
            }
        }.modifier(PageProtection(page: page))
    }
    private var bottomControls: some View {
        VStack(spacing: 10) {
            if exporting { ProgressView("Exporting…").font(.caption) }
            if showThumbnails {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(Array(livePages.enumerated()), id: \.element.id) { offset, page in
                                Button { currentID = page.id } label: {
                                    VStack(spacing: 4) {
                                        PageThumbnail(page: page).frame(width: 38, height: 50).clipShape(RoundedRectangle(cornerRadius: 3))
                                            .overlay { RoundedRectangle(cornerRadius: 3).stroke(current?.id == page.id ? FolioStyle.ink : .clear, lineWidth: 2) }
                                        if showNumbers { Text("\(offset + 1)").font(.system(size: 9)).foregroundStyle(.secondary) }
                                    }
                                }.buttonStyle(.plain).id(page.id).accessibilityLabel("Page \(offset + 1), \(page.title)")
                            }
                        }.padding(.horizontal, 16).padding(.top, 4)
                    }
                    .onChange(of: currentID) { _, id in withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) } }
                    .onAppear { proxy.scrollTo(initialID, anchor: .center) }
                }
            }
            HStack {
                Button("Previous page", systemImage: "chevron.left") { navigate(-1) }.labelStyle(.iconOnly).disabled(index == 0)
                Spacer()
                if showNumbers { Text("\(index + 1) of \(livePages.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                Spacer()
                Button("Next page", systemImage: "chevron.right") { navigate(1) }.labelStyle(.iconOnly).disabled(index >= livePages.count - 1)
            }.padding(.horizontal, 20)
        }.padding(.vertical, 10).glassEffect(in: .rect(cornerRadius: 22)).padding(.horizontal, 12).padding(.bottom, 5)
    }
    private func insertionAfter(_ page: NotePage) -> String? {
        guard let entries = page.book?.entries, let position = entries.firstIndex(where: { $0.id == "page:" + page.id.uuidString }), entries.indices.contains(position + 1) else { return nil }
        return entries[position + 1].id
    }
    private func open(_ name: String) { tool = name; sheet = true }
    private func navigate(_ delta: Int) { guard livePages.indices.contains(index + delta) else { return }; currentID = livePages[index + delta].id; FolioStyle.haptic() }
    private func markViewed() { guard let page = current, access.canRead(page) else { return }; page.lastViewedAt = .now; do { try context.save() } catch { actions.error = error.localizedDescription } }
    private func export(_ page: NotePage) {
        guard access.canRead(page) else { return }
        exporting = true; let pageIDs = [page.id]
        Task {
            defer { exporting = false }
            do { share = ExportFile(url: try await PDFExporter.shared.export(pageIDs: pageIDs, container: context.container, title: page.title)) }
            catch { actions.error = error.localizedDescription }
        }
    }
}
