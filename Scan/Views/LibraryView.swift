import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AccessController.self) private var access
    @Environment(LibraryActions.self) private var actions
    @Environment(CaptureRouter.self) private var router
    @Environment(WorkspaceFolder.self) private var workspace
    @Query(sort: \Notebook.createdAt) private var storedBooks: [Notebook]
    @Query(sort: \NotePage.rank) private var pages: [NotePage]
    @State private var importer = ImportCoordinator()
    @State private var newBook = false
    @State private var searching = false
    @State private var settings = false
    @State private var capture = false
    @State private var inbox = false
    @State private var autoScan = false
    @State private var trash = false
    @State private var favourites = false
    @AppStorage("shelfWidth") private var shelfWidth = 150.0
    private var books: [Notebook] { storedBooks.filter { $0.trashedAt == nil } }
    private var unfiledCount: Int { pages.filter { $0.book == nil && $0.trashedAt == nil }.count }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if workspace.error != nil {
                        Button("Working folder needs attention", systemImage: "exclamationmark.triangle") { settings = true }.font(.caption)
                    }
                    if unfiledCount > 0 {
                        Button { inbox = true } label: {
                            HStack {
                                Label("Unfiled", systemImage: "tray").font(.subheadline.weight(.medium))
                                Spacer(); Text("\(unfiledCount)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(17).background(.background, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: shelfWidth, maximum: shelfWidth + 55), spacing: 26)], spacing: 30) {
                        ForEach(books) { book in
                            NavigationLink { BookView(book: book, importer: importer) } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    BookCover(book: book)
                                    HStack {
                                        Text(book.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                        if book.isLocked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                                    }.foregroundStyle(.primary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    if books.isEmpty {
                        ContentUnavailableView("Your next chapter", systemImage: "books.vertical", description: Text("Create a book, or scan straight into Unfiled."))
                        Button("New book", systemImage: "plus") { newBook = true }.buttonStyle(.glass).frame(maxWidth: .infinity)
                        Button("Open a library folder", systemImage: "folder") { settings = true }.font(.subheadline).frame(maxWidth: .infinity)
                    }
                }.padding(26).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .background(FolioStyle.paper).navigationTitle("Books")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Unfiled", systemImage: "tray") { inbox = true }
                        Button("Favourites", systemImage: "star") { favourites = true }
                        Button("Recently Deleted", systemImage: "trash") { trash = true }
                        if actions.undoTitle != nil { Button("Undo", systemImage: "arrow.uturn.backward") { actions.undo() } }
                        Button("Settings", systemImage: "slider.horizontal.3") { settings = true }
                    } label: { Image(systemName: "line.3.horizontal") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Search", systemImage: "magnifyingglass") { searching = true } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New book", systemImage: "book.closed") { newBook = true }
                        Button("Import pages", systemImage: "folder") { autoScan = false; capture = true }
                    } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { autoScan = true; capture = true; FolioStyle.haptic() } label: {
                        Label("Scan", systemImage: "document.viewfinder").font(.subheadline.weight(.semibold)).padding(.horizontal, 24).padding(.vertical, 6)
                    }.buttonStyle(.glassProminent).disabled(importer.isBusy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) { if importer.isBusy { ImportProgress(importer: importer).padding(.horizontal) }; UndoBanner() }.padding(.bottom, 6)
            }
            .sheet(isPresented: $newBook) { BookEditor() }
            .sheet(isPresented: $searching) { SearchView(importer: importer) }
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(isPresented: $capture) { CaptureView(books: books, importer: importer, autoScan: autoScan) }
            .sheet(isPresented: $inbox) { NavigationStack { PageOrganiser(book: nil, importer: importer) } }
            .sheet(isPresented: $favourites) { FavouritePagesView(importer: importer) }
            .sheet(isPresented: $trash) { TrashView() }
            .task {
                handleRoute()
                await importer.resumePending(context: context)
            }
            .onChange(of: workspace.isConnected) { _, connected in
                if connected { Task { await importer.resumePending(context: context) } }
            }
            .onChange(of: router.route) { _, _ in handleRoute() }
            .alert("Something needs attention", isPresented: Binding(get: { importer.error != nil }, set: { if !$0 { importer.error = nil } })) {
                Button("OK") { importer.error = nil }
            } message: { Text(importer.error ?? "") }
            .modifier(ActionError())
        }
    }
    private func handleRoute() {
        guard let route = router.route else { return }
        router.route = nil
        if route == "scan" { autoScan = true; capture = true }
        if route == "inbox" { inbox = true }
    }
}

struct ImportProgress: View {
    let importer: ImportCoordinator
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(importer.progress).font(.caption).lineLimit(2)
            Spacer()
            Button("Stop", systemImage: "xmark") { importer.cancel() }.labelStyle(.iconOnly)
        }.padding(14).glassEffect(in: .rect(cornerRadius: 20)).accessibilityElement(children: .combine)
    }
}
