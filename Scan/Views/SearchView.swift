import SwiftUI
import SwiftData

struct SearchView: View {
    let importer: ImportCoordinator
    @Query(sort: \Notebook.createdAt) private var books: [Notebook]
    @Query(sort: \BookSection.rank) private var sections: [BookSection]
    @Query(sort: \NotePage.createdAt, order: .reverse) private var pages: [NotePage]
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var activeTerm = ""
    @State private var selectedPage: NotePage?
    private var term: String { activeTerm }
    private var matchingBooks: [Notebook] { term.isEmpty ? [] : books.filter { $0.title.localizedStandardContains(term) } }
    private var matchingSections: [BookSection] { term.isEmpty ? [] : sections.filter { $0.title.localizedStandardContains(term) } }
    private var matchingPages: [NotePage] {
        guard !term.isEmpty else { return [] }
        return pages.filter {
            $0.title.localizedStandardContains(term) || $0.text.localizedStandardContains(term) ||
            $0.tags.contains { $0.localizedStandardContains(term) } ||
            $0.detectedDate?.formatted(date: .abbreviated, time: .omitted).localizedStandardContains(term) == true
        }
    }
    var body: some View {
        NavigationStack {
            Group {
                if term.isEmpty {
                    ContentUnavailableView("Find a thought", systemImage: "text.magnifyingglass", description: Text("Search books, sections, tags and every recognised word."))
                } else if matchingBooks.isEmpty && matchingSections.isEmpty && matchingPages.isEmpty {
                    ContentUnavailableView.search(text: term)
                } else {
                    List {
                        if !matchingBooks.isEmpty {
                            Section("Books") { ForEach(matchingBooks) { book in
                                NavigationLink { BookView(book: book, importer: importer) } label: {
                                    Label { HighlightedText(value: book.title, query: term) } icon: { Image(systemName: book.symbol).foregroundStyle(FolioStyle.color(book.colorName)) }
                                }
                            } }
                        }
                        if !matchingSections.isEmpty {
                            Section("Sections") { ForEach(matchingSections) { section in
                                if let book = section.book {
                                    NavigationLink { BookView(book: book, importer: importer) } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            HighlightedText(value: section.title, query: term)
                                            Text(book.title).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            } }
                        }
                        if !matchingPages.isEmpty {
                            Section("Pages · \(matchingPages.count)") { ForEach(matchingPages) { page in
                                Button { focused = false; selectedPage = page } label: { PageRow(page: page, query: term) }.buttonStyle(.plain)
                            } }
                        }
                    }.scrollDismissesKeyboard(.interactively)
                }
            }.background(FolioStyle.paper)
            .navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            // SwiftUI's keyboard safe area places this bar immediately above the keyboard.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        HStack(spacing: 9) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search your library", text: $query).focused($focused)
                                .submitLabel(.search).autocorrectionDisabled().accessibilityIdentifier("librarySearch")
                            if !query.isEmpty {
                                Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }.labelStyle(.iconOnly).foregroundStyle(.secondary)
                            }
                        }.padding(.horizontal, 17).frame(height: 50).glassEffect(in: .capsule)
                        Button { focused = false; dismiss() } label: { Image(systemName: "xmark").frame(width: 50, height: 50) }
                            .glassEffect(.regular.interactive(), in: .circle).accessibilityLabel("Close search")
                    }
                }.padding(.horizontal, 16).padding(.vertical, 10)
            }
            .task { focused = true }
            .task(id: query) {
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                activeTerm = query.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .fullScreenCover(item: $selectedPage) { page in PageReader(pages: page.book?.orderedPages ?? [page], initialID: page.id, importer: importer, searchTerm: term) }
        }
    }
}
