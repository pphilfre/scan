import SwiftUI
import SwiftData

struct BookEditor: View {
    var book: Notebook?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var color = "sage"
    @State private var symbol = "book.closed"
    @State private var cover = "linen"
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        // A transient model is never inserted in the library.
                        BookCover(book: Notebook(title: title.isEmpty ? "Your next idea" : title, colorName: color, symbol: symbol, coverStyle: cover)).frame(width: 150)
                        Spacer()
                    }.listRowBackground(Color.clear).padding(.vertical)
                }
                Section("Book details") {
                    TextField("Title", text: $title).accessibilityIdentifier("bookTitle")
                    Picker("Cover", selection: $cover) { Text("Linen").tag("linen"); Text("Ruled").tag("ruled") }
                }
                Section("Colour") {
                    HStack(spacing: 14) {
                        ForEach(FolioStyle.colors, id: \.self) { name in
                            Button { color = name; FolioStyle.haptic() } label: {
                                Circle().fill(FolioStyle.color(name)).frame(width: 34, height: 34)
                                    .overlay { if color == name { Image(systemName: "checkmark").foregroundStyle(.white).font(.caption.bold()) } }
                            }.buttonStyle(.plain).accessibilityLabel(name).accessibilityAddTraits(color == name ? .isSelected : [])
                        }
                    }.padding(.vertical, 6)
                }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 15) {
                        ForEach(FolioStyle.symbols, id: \.self) { name in
                            Button { symbol = name; FolioStyle.haptic() } label: {
                                Image(systemName: name).font(.title3).frame(width: 44, height: 44)
                                    .background(symbol == name ? FolioStyle.color(color).opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityLabel(name)
                        }
                    }
                }
            }
            .navigationTitle(book == nil ? "New book" : "Edit book").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear { if let book { title = book.title; color = book.colorName; symbol = book.symbol; cover = book.coverStyle } }
            .alert("Couldn’t save book", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        }
    }
    private func save() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let book { book.title = clean; book.colorName = color; book.symbol = symbol; book.coverStyle = cover }
        else { context.insert(Notebook(title: clean, colorName: color, symbol: symbol, coverStyle: cover)) }
        do { try context.save(); dismiss() } catch { self.error = error.localizedDescription }
    }
}
