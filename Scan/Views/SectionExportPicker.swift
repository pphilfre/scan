import SwiftUI
import SwiftData

struct SectionExportPicker: View {
    let book: Notebook
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AccessController.self) private var access
    @Environment(LibraryActions.self) private var actions
    @State private var selection: Set<UUID> = []
    @State private var share: ExportFile?
    @State private var busy = false
    private var pages: [NotePage] {
        let ids = selection.reduce(into: Set<UUID>()) { $0.formUnion(book.descendantIDs(of: $1)) }
        return book.orderedPages.filter { $0.sectionID.map(ids.contains) == true }
    }
    var body: some View {
        NavigationStack {
            Group {
                if !access.canOpen(book) { BookLockView(book: book) }
                else { List(book.activeSections) { section in
                Button {
                    if selection.contains(section.id) { selection.remove(section.id) } else { selection.insert(section.id) }
                } label: {
                    HStack {
                        Image(systemName: selection.contains(section.id) ? "checkmark.circle.fill" : "circle")
                        Label(section.title, systemImage: section.symbol)
                        Spacer(); Text("\(book.pages(in: section).count)").font(.caption).foregroundStyle(.secondary)
                    }.padding(.leading, CGFloat(book.depth(of: section) * 14))
                }.buttonStyle(.plain)
            }
                }
            }
            .navigationTitle("Export sections").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        guard access.canOpen(book) else { return }
                        busy = true; let ids = pages.map(\.id)
                        Task {
                            defer { busy = false }
                            do { share = ExportFile(url: try await PDFExporter.shared.export(pageIDs: ids, container: context.container, title: book.title)) }
                            catch { actions.error = error.localizedDescription }
                        }
                    }.disabled(pages.isEmpty || busy || !access.canOpen(book))
                }
            }
            .overlay { if busy { ProgressView("Exporting…").padding().glassEffect() } }
            .sheet(item: $share) { ShareSheet(items: [$0.url]) }
        }
    }
}
