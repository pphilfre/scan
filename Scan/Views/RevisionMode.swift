import SwiftUI
import SwiftData

struct RevisionMode: View {
    let page: NotePage
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryActions.self) private var actions
    @Environment(AccessController.self) private var access
    @State private var image: UIImage?
    @State private var covers: [RecallCover] = []
    @State private var revealed: Set<UUID> = []
    @State private var arranging = true
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let image {
                    let scale = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                        ForEach($covers) { $cover in
                            RecallCoverView(cover: $cover, size: size, arranging: arranging, revealed: revealed.contains(cover.id), toggle: {
                                if revealed.contains(cover.id) { revealed.remove(cover.id) } else { revealed.insert(cover.id) }
                                FolioStyle.haptic()
                            }, remove: { covers.removeAll { $0.id == cover.id } })
                        }
                    }.frame(width: size.width, height: size.height).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.padding(12).background(FolioStyle.paper)
            .navigationTitle("Revision").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { save(); dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(arranging ? "Test myself" : "Arrange") { arranging.toggle(); revealed = [] }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Add cover", systemImage: "plus.rectangle") { covers.append(RecallCover()); arranging = true }
                    Spacer()
                    Button(revealed.isEmpty ? "Reveal all" : "Hide all", systemImage: revealed.isEmpty ? "eye" : "eye.slash") {
                        revealed = revealed.isEmpty ? Set(covers.map(\.id)) : []
                    }.disabled(covers.isEmpty)
                }
            }
            .task {
                covers = RecallCover.decode(page.revisionCoverData)
                let data = await PageImageRenderer.shared.render(PageSnapshot(page))
                if !Task.isCancelled { image = data.flatMap { UIImage(data: $0) } }
            }
            .interactiveDismissDisabled()
        }.modifier(PageProtection(page: page))
    }
    private func save() {
        guard access.canRead(page) else { return }
        actions.edit([page], in: context, name: "Revision covers") { page.revisionCoverData = RecallCover.encode(covers) }
    }
}

private struct RecallCoverView: View {
    @Binding var cover: RecallCover
    let size: CGSize
    let arranging: Bool
    let revealed: Bool
    let toggle: () -> Void
    let remove: () -> Void
    @State private var initial: NormalizedRect?
    var body: some View {
        RoundedRectangle(cornerRadius: 5).fill(FolioStyle.ink.opacity(revealed ? 0.08 : 1))
            .overlay { if !revealed { Image(systemName: arranging ? "arrow.up.and.down.and.arrow.left.and.right" : "hand.tap").font(.caption).foregroundStyle(.white.opacity(0.8)) } }
            .overlay(alignment: .bottomTrailing) {
                if arranging {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2).foregroundStyle(.white).frame(width: 32, height: 32).contentShape(Rectangle())
                        .highPriorityGesture(DragGesture().onChanged { value in
                            if initial == nil { initial = cover.rect }; guard let initial else { return }
                            var next = initial; next.width += value.translation.width / max(1, size.width); next.height += value.translation.height / max(1, size.height); cover.rect = next.clamped
                        }.onEnded { _ in initial = nil })
                }
            }
            .frame(width: cover.rect.width * size.width, height: cover.rect.height * size.height)
            .position(x: (cover.rect.x + cover.rect.width / 2) * size.width, y: (cover.rect.y + cover.rect.height / 2) * size.height)
            .onTapGesture { if !arranging { toggle() } }
            .gesture(DragGesture().onChanged { value in
                guard arranging else { return }
                if initial == nil { initial = cover.rect }; guard let initial else { return }
                var next = initial; next.x += value.translation.width / max(1, size.width); next.y += value.translation.height / max(1, size.height); cover.rect = next.clamped
            }.onEnded { _ in initial = nil })
            .contextMenu { if arranging { Button("Remove cover", systemImage: "trash", role: .destructive, action: remove) } }
            .accessibilityLabel(revealed ? "Revealed answer" : "Covered answer")
            .accessibilityAddTraits(.isButton).accessibilityAction { toggle() }
            .accessibilityAdjustableAction { direction in
                var next = cover.rect
                next.y += direction == .increment ? 0.03 : -0.03; cover.rect = next.clamped
            }
    }
}
