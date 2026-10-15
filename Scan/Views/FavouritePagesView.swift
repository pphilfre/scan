import SwiftUI
import SwiftData

struct FavouritePagesView: View {
    let importer: ImportCoordinator
    @Query(sort: \NotePage.createdAt, order: .reverse) private var pages: [NotePage]
    @Environment(AccessController.self) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var selected: NotePage?
    private var favourites: [NotePage] { pages.filter { $0.isFavourite && access.canRead($0) } }
    var body: some View {
        NavigationStack {
            List(favourites) { page in Button { selected = page } label: { PageRow(page: page) }.buttonStyle(.plain) }
                .overlay { if favourites.isEmpty { ContentUnavailableView("No favourites yet", systemImage: "star") } }
                .navigationTitle("Favourites").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .fullScreenCover(item: $selected) { page in PageReader(pages: page.book?.orderedPages ?? [page], initialID: page.id, importer: importer) }
        }
    }
}
