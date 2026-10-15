import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Notebook.createdAt) private var books: [Notebook]
    @Query(sort: \NotePage.createdAt, order: .reverse) private var pages: [NotePage]
    @State private var importer = ImportCoordinator()
    @State private var newBook = false
    @State private var searching = false
    @State private var settings = false
    @State private var capture = false
    @State private var selectedPage: NotePage?
    @State private var filter = "All books"
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 26)]
    private var recent: [NotePage] {
        Array(pages.filter { $0.lastViewedAt != nil }.sorted { ($0.lastViewedAt ?? .distantPast) > ($1.lastViewedAt ?? .distantPast) }.prefix(8))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if !recent.isEmpty && filter == "All books" { recentSection }
                    HStack {
                        Text(filter == "Favourites" ? "Saved for later" : "Your bookshelf")
                            .font(.system(.title2, design: .serif, weight: .medium))
                        Spacer()
                        Text("\(books.count) books").font(.caption).foregroundStyle(.secondary)
                    }
                    if filter == "Favourites" {
                        if pages.filter(\.isFavourite).isEmpty {
                            ContentUnavailableView("Keep the good pages close", systemImage: "star", description: Text("Favourite a page from its reader to find it here."))
                        }
                        ForEach(pages.filter(\.isFavourite)) { page in
                            Button { selectedPage = page } label: { PageRow(page: page, number: page.book?.orderedPages.firstIndex(where: { $0.id == page.id }).map { $0 + 1 }) }
                                .buttonStyle(.plain)
                        }
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                            ForEach(books) { book in
                                NavigationLink { BookView(book: book, importer: importer) } label: {
                                    VStack(alignment: .leading, spacing: 12) {
                                        BookCover(book: book)
                                        Text(book.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text("\(book.pages?.count ?? 0) pages").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain)
                            }
                            Button { newBook = true } label: {
                                VStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 9).strokeBorder(.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                                        .aspectRatio(0.73, contentMode: .fit)
                                        .overlay { Image(systemName: "plus").font(.title2.weight(.light)).foregroundStyle(.secondary) }
                                    Text("New book").font(.subheadline).foregroundStyle(.secondary)
                                    Text("Make room for ideas").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("newBook")
                        }
                    }
                    Label("Your thoughts. A little more organised.", systemImage: "leaf")
                        .font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.padding(.horizontal, 26).padding(.top, 12).padding(.bottom, 24).frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(FolioStyle.paper)
            .navigationTitle("Library").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Text("FOLIO").font(.system(size: 12, weight: .semibold, design: .serif)).tracking(3) }
                ToolbarItem(placement: .topBarTrailing) { Button("Settings", systemImage: "slider.horizontal.3") { settings = true } }
            }
            .safeAreaInset(edge: .bottom) { dock }
            .sheet(isPresented: $newBook) { BookEditor() }
            .sheet(isPresented: $searching) { SearchView(importer: importer) }
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(isPresented: $capture) { CaptureView(books: books, importer: importer) }
            .fullScreenCover(item: $selectedPage) { page in PageReader(pages: page.book?.orderedPages ?? [page], initialID: page.id, importer: importer) }
            .task {
                if books.isEmpty && !UserDefaults.standard.bool(forKey: "seededLibrary") {
                    context.insert(Notebook(title: "Maths", colorName: "sage", symbol: "function"))
                    context.insert(Notebook(title: "Physics", colorName: "blue", symbol: "atom"))
                    context.insert(Notebook(title: "Economics", colorName: "clay", symbol: "chart.line.uptrend.xyaxis"))
                    do { try context.save(); UserDefaults.standard.set(true, forKey: "seededLibrary") }
                    catch { importer.error = error.localizedDescription }
                }
                await importer.resumePending(context: context)
            }
            .alert("Something needs attention", isPresented: Binding(get: { importer.error != nil }, set: { if !$0 { importer.error = nil } })) {
                Button("OK") { importer.error = nil }
            } message: { Text(importer.error ?? "") }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
            Text("A place for\nevery thought.").font(.system(size: 39, weight: .regular, design: .serif)).tracking(-1.1)
                .fixedSize(horizontal: false, vertical: true)
            Text("From paper to possibility.").font(.subheadline).foregroundStyle(.secondary)
            Picker("Library filter", selection: $filter) {
                Text("All books").tag("All books")
                Text("Favourites").tag("Favourites")
            }.pickerStyle(.segmented).padding(.top, 12)
        }.padding(.bottom, 3)
    }
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick up where you left off").font(.subheadline.weight(.medium))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recent) { page in
                        Button { selectedPage = page } label: {
                            HStack(spacing: 10) {
                                PageThumbnail(page: page).frame(width: 40, height: 54).clipShape(RoundedRectangle(cornerRadius: 4))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(page.title).font(.caption.weight(.medium)).lineLimit(1)
                                    Text(page.book?.title ?? "Note").font(.caption2).foregroundStyle(.secondary)
                                }.frame(width: 140, alignment: .leading)
                            }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private var dock: some View {
        VStack(spacing: 10) {
            if importer.isBusy { ImportProgress(importer: importer) }
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    Button { searching = true; FolioStyle.haptic() } label: { Image(systemName: "magnifyingglass").frame(width: 48, height: 48) }
                        .glassEffect(.regular.interactive(), in: .circle).accessibilityLabel("Search library")
                    Button { capture = true; FolioStyle.haptic() } label: {
                        Label("Scan a note", systemImage: "document.viewfinder").font(.subheadline.weight(.semibold)).padding(.horizontal, 24).frame(height: 50)
                    }.buttonStyle(.glassProminent).tint(FolioStyle.ink).disabled(importer.isBusy)
                    Button { newBook = true } label: { Image(systemName: "plus").frame(width: 48, height: 48) }
                        .glassEffect(.regular.interactive(), in: .circle).accessibilityLabel("New book")
                }
            }
        }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
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
