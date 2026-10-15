import SwiftUI
import SwiftData

struct SectionEditor: View {
    let book: Notebook
    var section: BookSection?
    var initialParent: UUID?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryActions.self) private var actions
    @State private var title = ""
    @State private var color = "sage"
    @State private var symbol = "bookmark"
    @State private var style = "tab"
    @State private var parent: UUID?
    @State private var beforeID: String?
    private var parents: [BookSection] {
        let excluded = section.map { book.descendantIDs(of: $0.id) } ?? []
        return book.activeSections.filter { !excluded.contains($0.id) }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Divider") {
                    TextField("Name", text: $title)
                    Picker("Parent", selection: $parent) {
                        Text("Top level").tag(nil as UUID?)
                        ForEach(parents) { Text(String(repeating: "  ", count: book.depth(of: $0)) + $0.title).tag(Optional($0.id)) }
                    }
                    Picker("Insert before", selection: $beforeID) {
                        Text("End of section").tag(nil as String?)
                        ForEach(book.activeSections.filter { $0.parentID == parent && $0.id != section?.id }) { Text($0.title).tag(Optional("section:" + $0.id.uuidString)) }
                    }
                    Picker("Style", selection: $style) { Text("Tab").tag("tab"); Text("Band").tag("band"); Text("Minimal").tag("minimal") }
                }
                Section("Colour") { ColorChoices(selection: $color) }
                Section("Icon") { IconChoices(selection: $symbol) }
            }
            .navigationTitle(section == nil ? "New divider" : "Edit divider").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear {
                parent = section?.parentID ?? initialParent
                if let section { title = section.title; color = section.colorName; symbol = section.symbol; style = section.dividerStyle }
                else { color = book.colorName }
            }
        }
    }
    private func save() {
        let divider = section ?? BookSection(title: title, rank: book.nextRank, book: book)
        let old = (divider.title, divider.colorName, divider.symbol, divider.dividerStyle, divider.parentID)
        let wasNew = section == nil
        if wasNew { context.insert(divider) }
        divider.modifiedAt = .now
        divider.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        divider.colorName = color; divider.symbol = symbol; divider.dividerStyle = style; divider.parentID = parent
        if !wasNew && old.4 == parent && beforeID == nil {
            do { try context.save(); dismiss() } catch { actions.error = error.localizedDescription }
            return
        }
        var entries = book.entries
        let ids = book.descendantIDs(of: divider.id)
        let moving = entries.filter { entry in
            switch entry {
            case .section(let value): ids.contains(value.id)
            case .page(let value): value.sectionID.map(ids.contains) == true
            }
        }
        entries.removeAll { entry in moving.contains { $0.id == entry.id } }
        let anchor = beforeID ?? parent.flatMap { id in book.activeSections.first { $0.id == id }.flatMap { book.insertionID(afterSection: $0) } }
        let position = anchor.flatMap { id in entries.firstIndex { $0.id == id } } ?? entries.count
        let placements = book.entries.map { ($0, $0.rank) }
        entries.insert(contentsOf: moving, at: position); book.applyOrder(entries)
        do {
            try context.save()
            actions.register(wasNew ? "Add divider" : "Edit divider") {
                if wasNew { divider.trashedAt = .now }
                else { divider.title = old.0; divider.colorName = old.1; divider.symbol = old.2; divider.dividerStyle = old.3; divider.parentID = old.4 }
                for (entry, rank) in placements { switch entry { case .page(let page): page.rank = rank; case .section(let value): value.rank = rank } }
                book.applyOrder(book.entries); try context.save()
            }
            dismiss()
        } catch { context.rollback(); actions.error = error.localizedDescription }
    }
}

struct SectionTabs: View {
    let book: Notebook
    let jump: (BookSection) -> Void
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 5) {
                ForEach(book.activeSections) { section in
                    Button { jump(section); FolioStyle.haptic() } label: {
                        Image(systemName: section.symbol).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white).frame(width: 32, height: 44)
                            .background(FolioStyle.color(section.colorName).gradient, in: UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7))
                    }.buttonStyle(.plain).accessibilityLabel("Jump to \(section.title)")
                        .contextMenu { Text(section.title) }
                }
            }.padding(.vertical, 8)
        }.frame(width: 33).fixedSize(horizontal: true, vertical: false)
    }
}
