import SwiftUI
import SwiftData

struct BookEditor: View {
    var book: Notebook?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var color = "sage"
    @State private var secondColor = "blue"
    @State private var symbol = "book.closed"
    @State private var cover = "linen"
    @State private var spine = ""
    @State private var texture = 0.16
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BookCover(appearance: CoverAppearance(title: title.isEmpty ? "New book" : title, color: color, secondColor: secondColor, symbol: symbol, style: cover, spine: spine, texture: texture))
                        .frame(width: 145).frame(maxWidth: .infinity).padding(.vertical, 8).listRowBackground(Color.clear)
                }
                Section("Book") {
                    TextField("Title", text: $title).accessibilityIdentifier("bookTitle")
                    TextField("Spine label", text: $spine)
                }
                Section("Cover") {
                    Picker("Finish", selection: $cover) {
                        ForEach(["solid", "gradient", "linen", "paper", "ruled"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    ColorChoices(selection: $color)
                    if cover == "gradient" { ColorChoices(selection: $secondColor) }
                    if ["linen", "paper", "ruled"].contains(cover) { Slider(value: $texture, in: 0.04...0.35) { Text("Texture intensity") } }
                }
                Section("Icon") {
                    IconChoices(selection: $symbol)
                    TextField("SF Symbol name", text: $symbol).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .navigationTitle(book == nil ? "New book" : "Customise book").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear {
                if let book {
                    title = book.title; color = book.colorName; symbol = book.symbol; cover = book.coverStyle
                    secondColor = book.gradientColorName; spine = book.spineLabel; texture = book.textureStrength
                }
            }
            .alert("Couldn’t save book", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        }
    }
    private func save() {
        let target = book ?? Notebook(title: title)
        if book == nil { context.insert(target) }
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.colorName = color; target.symbol = symbol; target.coverStyle = cover
        target.modifiedAt = .now
        target.spineLabel = spine; target.gradientColorName = secondColor; target.textureStrength = texture
        do { try context.save(); dismiss() } catch { self.error = error.localizedDescription }
    }
}

struct ColorChoices: View {
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 14) {
            ForEach(FolioStyle.colors, id: \.self) { name in
                Button { selection = name; FolioStyle.haptic() } label: {
                    Circle().fill(FolioStyle.color(name)).frame(width: 30, height: 30)
                        .overlay { if selection == name { Image(systemName: "checkmark").foregroundStyle(.white).font(.caption.bold()) } }
                }.buttonStyle(.plain).accessibilityLabel(name).accessibilityAddTraits(selection == name ? .isSelected : [])
            }
        }.padding(.vertical, 5)
    }
}

struct IconChoices: View {
    @Binding var selection: String
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
            ForEach(FolioStyle.symbols + ["bookmark", "tag", "square.stack", "graduationcap"], id: \.self) { name in
                Button { selection = name } label: {
                    Image(systemName: name).font(.title3).frame(width: 40, height: 40)
                        .background(selection == name ? FolioStyle.ink.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityLabel(name)
            }
        }
    }
}
