import SwiftUI
import SwiftData

struct TrashView: View {
    @Query(sort: \Notebook.createdAt) private var books: [Notebook]
    @Query(sort: \NotePage.createdAt) private var pages: [NotePage]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AccessController.self) private var access
    @Environment(LibraryActions.self) private var actions
    var body: some View {
        NavigationStack {
            List {
                Section("Books") {
                    ForEach(books.filter { $0.trashedAt != nil }) { book in
                        HStack {
                            Label(book.title, systemImage: book.isLocked ? "lock" : book.symbol)
                            Spacer()
                            Button("Restore") {
                                Task {
                                    if book.isLocked && !access.canOpen(book) { await access.unlock(book) }
                                    guard access.canOpen(book) else { return }
                                    book.trashedAt = nil; book.modifiedAt = .now
                                    do { try LibraryPersistence.save(context); actions.register("Restore book") { book.trashedAt = .now; book.modifiedAt = .now; try LibraryPersistence.save(context) } }
                                    catch { actions.error = error.localizedDescription }
                                }
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                Section("Pages") {
                    ForEach(pages.filter { $0.trashedAt != nil }) { page in
                        HStack {
                            if let book = page.book, !access.canOpen(book) {
                                Label("Locked note", systemImage: "lock")
                                Spacer()
                                Button("Unlock") { Task { await access.unlock(book) } }
                            } else {
                                Text(page.title).lineLimit(1)
                                Spacer()
                                Button("Restore") {
                                    actions.edit([page], in: context, name: "Restore pages") {
                                        page.trashedAt = nil
                                        if page.book?.trashedAt != nil { page.book = nil; page.sectionID = nil }
                                    }
                                }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .overlay {
                if books.allSatisfy({ $0.trashedAt == nil }) && pages.allSatisfy({ $0.trashedAt == nil }) {
                    ContentUnavailableView("Nothing deleted", systemImage: "trash")
                }
            }
            .navigationTitle("Recently Deleted").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .safeAreaInset(edge: .bottom) { UndoBanner().padding(.bottom, 6) }
            .modifier(ActionError())
        }
    }
}
