import SwiftUI
import SwiftData

struct EnhancementEditor: View {
    let pages: [NotePage]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryActions.self) private var actions
    @Environment(AccessController.self) private var access
    @State private var adjustments = ImageAdjustments()
    @State private var preview: UIImage?
    @State private var ready = false
    private var allowed: Bool { pages.allSatisfy(access.canRead) }
    var body: some View {
        NavigationStack {
            Form {
                if allowed {
                    Section {
                        if let preview {
                            Image(uiImage: preview).resizable().scaledToFit()
                                .overlay { GeometryReader { geometry in CropOverlay(rect: $adjustments.crop, size: geometry.size) } }.frame(maxHeight: 400)
                                .padding(.vertical, 10)
                        } else { ProgressView("Opening page…").frame(maxWidth: .infinity, minHeight: 250) }
                    }.listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                    Section("Enhancement") {
                        Picker("Filter", selection: $adjustments.filter) {
                            Text("Colour").tag("original"); Text("Grey").tag("grayscale"); Text("Ink").tag("mono"); Text("Warm").tag("sepia")
                        }.pickerStyle(.segmented)
                        LabeledContent("Straighten") { Slider(value: $adjustments.straighten, in: -15...15, step: 0.1).frame(maxWidth: 190) }
                        LabeledContent("Brightness") { Slider(value: $adjustments.brightness, in: -0.3...0.3).frame(maxWidth: 190) }
                        LabeledContent("Contrast") { Slider(value: $adjustments.contrast, in: 0.5...2).frame(maxWidth: 190) }
                    }
                    Section {
                        DisclosureGroup("Crop controls") {
                            cropSlider("Width", keyPath: \.width, range: 0.04...1)
                            cropSlider("Height", keyPath: \.height, range: 0.04...1)
                            cropSlider("Horizontal position", keyPath: \.x, range: 0...1)
                            cropSlider("Vertical position", keyPath: \.y, range: 0...1)
                        }
                        Button("Reset") { adjustments = ImageAdjustments() }
                    } footer: { Text(pages.count > 1 ? "The same settings apply to all selected pages. Originals are preserved." : "Drag the crop handles to frame the page. You can reset these changes at any time.") }
                } else { Text("Unlock the book to edit these pages.") }
            }
            .navigationTitle("Crop & enhance").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard allowed else { return }
                        actions.edit(pages, in: context, name: "Enhance pages") { for page in pages { page.enhancementData = adjustments.data } }
                        dismiss()
                    }.disabled(!ready || !allowed)
                }
            }
            .onAppear { adjustments = pages.first.map { ImageAdjustments(data: $0.enhancementData) } ?? ImageAdjustments(); ready = true }
            .task(id: previewKey) {
                guard ready, allowed, let page = pages.first else { return }
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                var snapshot = PageSnapshot(page)
                snapshot.adjustments = adjustments; snapshot.adjustments.crop = NormalizedRect(); snapshot.rotation = 0
                let data = await PageImageRenderer.shared.preview(snapshot)
                guard !Task.isCancelled else { return }
                preview = data.flatMap { UIImage(data: $0) }
            }
        }
    }
    private var previewKey: String { "\(ready)-\(adjustments.straighten)-\(adjustments.brightness)-\(adjustments.contrast)-\(adjustments.filter)" }
    private func cropSlider(_ title: String, keyPath: WritableKeyPath<NormalizedRect, Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            Slider(value: Binding(get: { adjustments.crop[keyPath: keyPath] }, set: { value in
                var rect = adjustments.crop; rect[keyPath: keyPath] = value; adjustments.crop = rect.clamped
            }), in: range).frame(maxWidth: 180)
        }
    }
}

struct CropOverlay: View {
    @Binding var rect: NormalizedRect
    let size: CGSize
    @State private var initial: NormalizedRect?
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.black.opacity(0.28)).reverseMask {
                Rectangle().frame(width: rect.width * size.width, height: rect.height * size.height)
                    .position(x: (rect.x + rect.width / 2) * size.width, y: (rect.y + rect.height / 2) * size.height)
            }.allowsHitTesting(false)
            Rectangle().stroke(.white, lineWidth: 2).frame(width: rect.width * size.width, height: rect.height * size.height)
                .contentShape(Rectangle()).position(x: (rect.x + rect.width / 2) * size.width, y: (rect.y + rect.height / 2) * size.height)
                .gesture(DragGesture().onChanged { gesture in
                    if initial == nil { initial = rect }; guard let initial else { return }
                    var next = initial; next.x += gesture.translation.width / max(1, size.width); next.y += gesture.translation.height / max(1, size.height); rect = next.clamped
                }.onEnded { _ in initial = nil })
            handle(topLeft: true).position(x: rect.x * size.width, y: rect.y * size.height)
            handle(topLeft: false).position(x: (rect.x + rect.width) * size.width, y: (rect.y + rect.height) * size.height)
        }.clipped()
    }
    private func handle(topLeft: Bool) -> some View {
        Circle().fill(.white).frame(width: 14, height: 14).frame(width: 40, height: 40).contentShape(Rectangle())
            .accessibilityLabel(topLeft ? "Top left crop handle" : "Bottom right crop handle")
            .highPriorityGesture(DragGesture().onChanged { gesture in
                if initial == nil { initial = rect }; guard let initial else { return }
                let dx = gesture.translation.width / max(1, size.width), dy = gesture.translation.height / max(1, size.height)
                var next = initial
                if topLeft {
                    let right = initial.x + initial.width, bottom = initial.y + initial.height
                    next.x = min(right - 0.04, max(0, initial.x + dx)); next.y = min(bottom - 0.04, max(0, initial.y + dy))
                    next.width = right - next.x; next.height = bottom - next.y
                } else {
                    next.width = max(0.04, min(1 - initial.x, initial.width + dx)); next.height = max(0.04, min(1 - initial.y, initial.height + dy))
                }
                rect = next.clamped
            }.onEnded { _ in initial = nil })
    }
}

extension View {
    func reverseMask<Mask: View>(@ViewBuilder mask: () -> Mask) -> some View {
        self.mask { Rectangle().overlay { mask().blendMode(.destinationOut) } }
    }
}
