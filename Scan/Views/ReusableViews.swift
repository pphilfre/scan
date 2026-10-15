import SwiftUI
import SwiftData

struct UndoBanner: View {
    @Environment(LibraryActions.self) private var actions
    var body: some View {
        if actions.noticeVisible, let title = actions.undoTitle {
            HStack {
                Text(title).font(.caption).lineLimit(1)
                Spacer()
                Button("Undo", systemImage: "arrow.uturn.backward") { actions.undo() }.font(.caption.weight(.semibold))
            }.padding(.horizontal, 18).padding(.vertical, 12).glassEffect(in: .capsule)
                .padding(.horizontal).transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct ActionError: ViewModifier {
    @Environment(LibraryActions.self) private var actions
    func body(content: Content) -> some View {
        content.alert("Couldn’t save changes", isPresented: Binding(get: { actions.error != nil }, set: { if !$0 { actions.error = nil } })) {
            Button("OK") { actions.error = nil }
        } message: { Text(actions.error ?? "") }
    }
}

struct DisplayPreferences: View {
    @AppStorage("shelfWidth") private var shelfWidth = 150.0
    @AppStorage("thumbnailWidth") private var thumbnailWidth = 105.0
    @AppStorage("pageLayout") private var layout = "grid"
    @AppStorage("showPageNumbers") private var numbers = true
    @AppStorage("showThumbnails") private var thumbnails = true
    @AppStorage("pageCurl") private var curl = true
    @AppStorage("readerFullscreen") private var fullscreen = false
    @AppStorage("readingPaper") private var paper = "system"
    var body: some View {
        Section("Layout") {
            LabeledContent("Book size") { Slider(value: $shelfWidth, in: 115...220, step: 5).frame(maxWidth: 170) }
            LabeledContent("Thumbnail size") { Slider(value: $thumbnailWidth, in: 75...200, step: 5).frame(maxWidth: 170) }
            Picker("Pages", selection: $layout) { Text("Grid").tag("grid"); Text("List").tag("list") }
        }
        Section("Reading") {
            Toggle("Page numbers", isOn: $numbers)
            Toggle("Thumbnail strip", isOn: $thumbnails)
            Toggle("Page-turn animation", isOn: $curl)
            Toggle("Open in full screen", isOn: $fullscreen)
            Picker("Paper", selection: $paper) { Text("Automatic").tag("system"); Text("Warm").tag("warm"); Text("Dark").tag("dark") }
        }
    }
}

struct PageThumbnail: View {
    let page: NotePage
    @Environment(\.modelContext) private var context
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Color.white
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "document").foregroundStyle(.secondary) }
        }.clipped().accessibilityHidden(true)
        .task(id: page.visualVersion) {
            let version = page.visualVersion
            let key = page.id.uuidString + version.uuidString
            if page.thumbnailVersion == version {
                image = ThumbnailMemory.shared.image(data: page.thumbnailData, key: key)
            } else {
                if page.thumbnailVersion == nil { image = UIImage(data: page.thumbnailData) }
                let snapshot = PageSnapshot(page)
                guard let data = await PageImageRenderer.shared.render(snapshot, maximum: 500), !Task.isCancelled,
                      !page.isDeleted, page.visualVersion == version else { return }
                page.thumbnailData = data; page.thumbnailVersion = version
                image = ThumbnailMemory.shared.image(data: data, key: key)
                do { try context.save() } catch { /* The original and edit state already remain saved. */ }
            }
        }
    }
}

struct PageRow: View {
    let page: NotePage
    var number: Int? = nil
    var query: String = ""
    var body: some View {
        HStack(spacing: 14) {
            PageThumbnail(page: page).frame(width: 48, height: 66).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 5) {
                HighlightedText(value: page.title, query: query).font(.subheadline.weight(.medium)).lineLimit(1)
                if !query.isEmpty {
                    HighlightedText(value: SmartMetadata.snippet(page.text, matching: query), query: query).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text(page.text.isEmpty ? (page.recognitionState == "recognising" ? "Recognising…" : page.createdAt.formatted(date: .abbreviated, time: .omitted)) : page.text.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let number { Text("\(number)").monospacedDigit() }
                    if page.isBookmarked { Image(systemName: "bookmark.fill") }
                    if page.isFavourite { Image(systemName: "star.fill") }
                    if !page.tags.isEmpty { Text(page.tags.map { "#" + $0 }.joined(separator: " ")).lineLimit(1) }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 5).contentShape(Rectangle())
    }
}

struct PageProtection: ViewModifier {
    let page: NotePage
    @Environment(\.dismiss) private var dismiss
    @Environment(AccessController.self) private var access
    func body(content: Content) -> some View {
        if page.trashedAt != nil || page.book?.trashedAt != nil {
            VStack { ContentUnavailableView("Page is in Recently Deleted", systemImage: "trash"); Button("Close") { dismiss() } }
        } else if access.canRead(page) { content }
        else if let book = page.book { BookLockView(book: book) }
        else { LibraryLockView() }
    }
}
