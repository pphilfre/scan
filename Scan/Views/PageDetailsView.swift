import SwiftUI
import SwiftData

struct PageDetailsView: View {
    @Bindable var page: NotePage
    let importer: ImportCoordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryActions.self) private var actions
    @Environment(AccessController.self) private var access
    @State private var title = ""
    @State private var text = ""
    @State private var tags = ""
    @State private var sectionID: UUID?
    @State private var suggestedNewSection: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Page title", text: $title)
                    TextField("Tags, separated by commas", text: $tags).textInputAutocapitalization(.never)
                    if let book = page.book {
                        Picker("Section", selection: $sectionID) {
                            Text("Before first divider").tag(nil as UUID?)
                            ForEach((book.sections ?? []).sorted { $0.rank < $1.rank }) { Text($0.title).tag(Optional($0.id)) }
                        }
                    }
                    if let date = page.detectedDate { LabeledContent("Detected date", value: date.formatted(date: .abbreviated, time: .omitted)) }
                }
                if !page.suggestedSection.isEmpty && page.sectionID == nil {
                    Section("Suggested section") {
                        Button(suggestedNewSection == nil ? "File under \(page.suggestedSection)" : "Will create \(page.suggestedSection)", systemImage: "sparkles") { useSuggestion() }
                    }
                }
                Section {
                    TextEditor(text: $text).frame(minHeight: 320).font(.body).accessibilityLabel("Recognised text")
                } header: { Text("Editable text") } footer: { Text("Corrections update search. Your original scan stays saved alongside this text.") }
            }
            .navigationTitle("Edit page").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { title = page.title; text = page.text; tags = page.tags.joined(separator: ", "); sectionID = page.sectionID }
        }.modifier(PageProtection(page: page))
    }
    private func useSuggestion() {
        guard let book = page.book else { return }
        if let section = book.sections?.first(where: { $0.title.localizedStandardCompare(page.suggestedSection) == .orderedSame }) { sectionID = section.id }
        else {
            suggestedNewSection = page.suggestedSection
        }
    }
    private func save() {
        guard access.canRead(page) else { return }
        actions.edit([page], in: context, name: "Edit page") {
            page.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            page.text = text
            page.tags = Array(Set(tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
            if let suggestedNewSection, let book = page.book {
                let section = BookSection(title: suggestedNewSection, rank: book.nextRank, book: book)
                context.insert(section); sectionID = section.id
            }
            if page.sectionID != sectionID, let book = page.book {
                var entries = book.entries.filter { $0.id != "page:" + page.id.uuidString }
                let position: Int
                if let sectionID, let index = entries.firstIndex(where: {
                    if case .section(let section) = $0 { return section.id == sectionID }; return false
                }) { position = index + 1 } else { position = 0 }
                entries.insert(.page(page), at: position); book.applyOrder(entries)
            }
        }
        dismiss()
    }
}
