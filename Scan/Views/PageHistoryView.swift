import SwiftUI
import SwiftData

struct PageHistoryView: View {
    let page: NotePage
    @Query(sort: \PageRevision.createdAt, order: .reverse) private var revisions: [PageRevision]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryActions.self) private var actions
    @Environment(AccessController.self) private var access
    @State private var selected: PageRevision?
    var body: some View {
        NavigationStack {
            List(revisions.filter { $0.pageID == page.id }) { revision in
                Button { selected = revision } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(revision.reason).font(.subheadline.weight(.medium))
                        Text(revision.createdAt.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                        if let state = try? JSONDecoder().decode(PageState.self, from: revision.payload) { Text(state.text.isEmpty ? state.title : state.text).font(.caption).lineLimit(2).foregroundStyle(.secondary) }
                    }
                }.buttonStyle(.plain)
            }
            .overlay { if !revisions.contains(where: { $0.pageID == page.id }) { ContentUnavailableView("No earlier versions", systemImage: "clock.arrow.circlepath") } }
            .navigationTitle("Version history").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $selected) { revision in
                NavigationStack {
                    if let state = try? JSONDecoder().decode(PageState.self, from: revision.payload) {
                        ScrollView { VStack(alignment: .leading, spacing: 18) {
                            Text(state.title).font(.system(.title, design: .serif))
                            Text(state.text).textSelection(.enabled)
                            Text("Includes the saved annotations, enhancements and tags.").font(.caption).foregroundStyle(.secondary)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading) }
                        .navigationTitle("Saved version").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selected = nil } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Restore") {
                                    guard access.canRead(page) else { return }
                                    actions.edit([page], in: context, name: "Restore version") {
                                        let currentBook = page.book
                                        state.apply(to: page, in: context)
                                        if let target = page.book, target.trashedAt != nil || !access.canOpen(target) { page.book = currentBook; page.sectionID = nil }
                                        page.trashedAt = nil
                                    }
                                    selected = nil
                                }
                            }
                        }
                    } else { ContentUnavailableView("Version unavailable", systemImage: "exclamationmark.triangle") }
                }.modifier(PageProtection(page: page))
            }
        }.modifier(PageProtection(page: page))
    }
}

struct PageLinksView: View {
    let page: NotePage
    let importer: ImportCoordinator
    @Query(sort: \NotePage.createdAt, order: .reverse) private var pages: [NotePage]
    @Query private var links: [PageLink]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AccessController.self) private var access
    @Environment(LibraryActions.self) private var actions
    @State private var adding = false
    @State private var query = ""
    @State private var selected: NotePage?
    private var related: [PageLink] { links.filter { $0.removedAt == nil && ($0.sourceID == page.id || $0.targetID == page.id) } }
    var body: some View {
        NavigationStack {
            List {
                ForEach(related) { link in
                    let id = link.sourceID == page.id ? link.targetID : link.sourceID
                    if let target = pages.first(where: { $0.id == id && $0.trashedAt == nil && $0.book?.trashedAt == nil }) {
                        Button {
                            Task {
                                if let book = target.book, !access.canOpen(book) { await access.unlock(book) }
                                if access.canRead(target) { selected = target }
                            }
                        } label: {
                            if access.canRead(target) { PageRow(page: target) }
                            else { Label("Locked linked note", systemImage: "lock") }
                        }.buttonStyle(.plain)
                        .swipeActions { Button("Unlink", role: .destructive) { link.removedAt = .now; save(); actions.register("Remove link") { link.removedAt = nil; try context.save() } } }
                    } else { Label("Linked page is in Recently Deleted", systemImage: "tray") }
                }
            }
            .overlay { if related.isEmpty { ContentUnavailableView("Related pages", systemImage: "link", description: Text("Connect ideas across your books.")) } }
            .navigationTitle("Related pages").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Link page", systemImage: "plus") { adding = true } }
            }
            .sheet(isPresented: $adding) {
                NavigationStack {
                    List(pages.filter { target in
                        target.id != page.id && access.canRead(target) &&
                        !related.contains(where: { $0.sourceID == target.id || $0.targetID == target.id }) &&
                        (query.isEmpty || target.title.localizedStandardContains(query) || target.text.localizedStandardContains(query))
                    }) { target in
                        Button {
                            guard access.canRead(page), access.canRead(target) else { return }
                            let link = PageLink(source: page.id, target: target.id); context.insert(link); save()
                            actions.register("Link page") { link.removedAt = .now; try context.save() }; adding = false
                        } label: { VStack(alignment: .leading, spacing: 3) { Text(target.title); Text(target.book?.title ?? "Unfiled").font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain)
                    }.searchable(text: $query, prompt: "Find a page")
                    .navigationTitle("Link a page").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } } }
                }.modifier(PageProtection(page: page))
            }
            .fullScreenCover(item: $selected) { target in PageReader(pages: target.book?.orderedPages ?? [target], initialID: target.id, importer: importer) }
        }.modifier(PageProtection(page: page))
    }
    private func save() { do { try context.save() } catch { actions.error = error.localizedDescription } }
}
