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
    @State private var currentID: UUID?
    @State private var textMode = false
    @State private var fullScreen = false
    @State private var annotations = false
    @State private var details = false
    @State private var movePage = false
    @State private var rerunOCR = false
    @State private var share: ExportFile?
    @State private var exporting = false
    private var livePages: [NotePage] { pages.filter { !$0.isDeleted } }
    private var current: NotePage? { livePages.first { $0.id == (currentID ?? initialID) } ?? livePages.first }
    private var index: Int { livePages.firstIndex { $0.id == current?.id } ?? 0 }
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground).ignoresSafeArea()
                if let page = current {
                    if textMode {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                Text(page.title).font(.system(.title, design: .serif))
                                if page.recognitionState == "recognising" || page.recognitionState == "pending" {
                                    ProgressView("Recognising handwriting…")
                                } else if page.text.isEmpty {
                                    ContentUnavailableView("No text recognised yet", systemImage: "text.viewfinder", description: Text("Try recognition again or add text using Edit text. Your original scan is always available."))
                                } else {
                                    HighlightedText(value: page.text, query: searchTerm).font(.body).lineSpacing(7).textSelection(.enabled)
                                    Text(page.recognitionConfidence < 0.75 ? "Handwriting may need a quick review." : "Recognised on your device. Review for accuracy.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(28).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
                        }
                    } else {
                        NativePageTurner(pages: livePages, currentID: Binding(get: { current?.id ?? initialID }, set: { currentID = $0 }), reduceMotion: reduceMotion)
                            .ignoresSafeArea(edges: fullScreen ? .all : [])
                    }
                }
            }
            .navigationTitle(fullScreen ? "" : (current?.book?.title ?? "Note")).navigationBarTitleDisplayMode(.inline)
            .toolbar(fullScreen ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $textMode) { Image(systemName: "document").tag(false); Image(systemName: "text.alignleft").tag(true) }
                        .pickerStyle(.segmented).frame(width: 112).accessibilityLabel("Original scan or recognised text")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let page = current {
                        Menu {
                            Button("Edit details & text", systemImage: "pencil") { details = true }
                            Button("Annotate", systemImage: "pencil.tip.crop.circle") { annotations = true }
                            Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") { withAnimation(.smooth) { fullScreen = true; textMode = false } }
                            Button(page.isFavourite ? "Remove favourite" : "Favourite", systemImage: page.isFavourite ? "star.slash" : "star") { page.isFavourite.toggle(); save() }
                            Button("Rotate clockwise", systemImage: "rotate.right") { page.rotation = (page.rotation + 1) % 4; save(); FolioStyle.haptic() }
                            Button("Duplicate", systemImage: "plus.square.on.square") { if let book = page.book { context.insert(page.copy(to: book)); save() } }
                            Button("Move to book", systemImage: "folder") { movePage = true }
                            Button("Recognise text again", systemImage: "text.viewfinder") { rerunOCR = true }
                                .disabled(page.recognitionState == "recognising")
                            Button("Export page as PDF", systemImage: "square.and.arrow.up") { export(page) }.disabled(exporting)
                        } label: { Image(systemName: "ellipsis") }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !fullScreen { bottomControls }
            }
            .overlay(alignment: .topTrailing) {
                if fullScreen {
                    Button { withAnimation(.smooth) { fullScreen = false } } label: { Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 44, height: 44) }
                        .glassEffect(in: .circle).padding().accessibilityLabel("Exit full screen")
                }
            }
            .sheet(isPresented: $details) { if let page = current { PageDetailsView(page: page, importer: importer) } }
            .sheet(isPresented: $annotations) { if let page = current { AnnotationEditor(page: page, importer: importer) } }
            .sheet(isPresented: $movePage) { if let page = current { MovePageView(page: page, importer: importer, onMoved: { dismiss() }) } }
            .sheet(item: $share) { ShareSheet(items: [$0.url]) }
            .confirmationDialog("Replace the edited text with a new recognition result?", isPresented: $rerunOCR, titleVisibility: .visible) {
                Button("Recognise again") { if let page = current { Task { await importer.recognise(page, context: context) } } }
            }
            .onAppear { currentID = initialID; markViewed() }
            .onChange(of: currentID) { _, _ in markViewed() }
            .onChange(of: textMode) { _, _ in FolioStyle.haptic() }
            .alert("Something needs attention", isPresented: Binding(get: { importer.error != nil }, set: { if !$0 { importer.error = nil } })) {
                Button("OK") { importer.error = nil }
            } message: { Text(importer.error ?? "") }
        }
    }
    private var bottomControls: some View {
        VStack(spacing: 12) {
            if exporting { ProgressView("Creating PDF…").font(.caption) }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(livePages.enumerated()), id: \.element.id) { offset, page in
                            Button { withAnimation(.smooth) { currentID = page.id } } label: {
                                VStack(spacing: 5) {
                                    PageThumbnail(page: page).frame(width: 40, height: 52).clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay { RoundedRectangle(cornerRadius: 4).stroke(current?.id == page.id ? FolioStyle.ink : .clear, lineWidth: 2) }
                                    Text("\(offset + 1)").font(.system(size: 9)).foregroundStyle(current?.id == page.id ? .primary : .secondary)
                                }
                            }.buttonStyle(.plain).id(page.id).accessibilityLabel("Page \(offset + 1), \(page.title)")
                        }
                    }.padding(.horizontal, 18).padding(.top, 5)
                }
                .onChange(of: currentID) { _, id in withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) } }
                .onAppear { proxy.scrollTo(initialID, anchor: .center) }
            }
            HStack {
                Button("Previous page", systemImage: "chevron.left") { navigate(-1) }.labelStyle(.iconOnly).disabled(index == 0)
                Spacer()
                Text("\(index + 1) of \(livePages.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button("Next page", systemImage: "chevron.right") { navigate(1) }.labelStyle(.iconOnly).disabled(index >= livePages.count - 1)
            }.padding(.horizontal, 22)
        }.padding(.vertical, 12).glassEffect(in: .rect(cornerRadius: 26)).padding(.horizontal, 14).padding(.bottom, 8)
    }
    private func navigate(_ delta: Int) {
        guard livePages.indices.contains(index + delta) else { return }
        currentID = livePages[index + delta].id
        FolioStyle.haptic()
    }
    private func markViewed() { current?.lastViewedAt = .now; save() }
    private func save() { do { try context.save() } catch { importer.error = error.localizedDescription } }
    private func export(_ page: NotePage) {
        exporting = true
        let snapshot = PageSnapshot(page)
        let title = page.title
        Task {
            defer { exporting = false }
            do { share = ExportFile(url: try await PDFExporter.shared.export([snapshot], title: title)) }
            catch { importer.error = error.localizedDescription }
        }
    }
}
