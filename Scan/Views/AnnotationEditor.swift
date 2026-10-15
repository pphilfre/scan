import SwiftUI
import SwiftData
import PencilKit

struct AnnotationEditor: View {
    let page: NotePage
    let importer: ImportCoordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()
    @State private var image: UIImage?
    var body: some View {
        NavigationStack {
            Group {
                if let image { InkCanvas(image: image, canvas: canvas, rotation: page.rotation) }
                else { ProgressView("Opening page…") }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Annotate").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        page.drawingData = canvas.drawing.dataRepresentation()
                        do { try context.save(); dismiss() } catch { importer.error = error.localizedDescription }
                    }.fontWeight(.semibold).disabled(image == nil)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { canvas.undoManager?.undo() }
                    Spacer()
                    Text("Draw with a finger or Apple Pencil").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Redo", systemImage: "arrow.uturn.forward") { canvas.undoManager?.redo() }
                }
            }
            .onAppear {
                image = PageRendering.baseImage(page.imageData)
                canvas.drawing = (try? PKDrawing(data: page.drawingData)) ?? PKDrawing()
            }
        }.interactiveDismissDisabled()
    }
}

struct InkCanvas: UIViewRepresentable {
    let image: UIImage
    let canvas: PKCanvasView
    let rotation: Int
    func makeUIView(context: Context) -> InkSurface { InkSurface(image: image, canvas: canvas, rotation: rotation) }
    func updateUIView(_ view: InkSurface, context: Context) {}
}

final class InkSurface: UIView, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let paper = UIView()
    private let pageContainer = UIView()
    private let canvas: PKCanvasView
    private let picker = PKToolPicker()
    private let pageSize: CGSize
    private var previousSize: CGSize = .zero
    init(image: UIImage, canvas: PKCanvasView, rotation: Int) {
        self.canvas = canvas
        let size = CGSize(width: 1000, height: 1000 * image.size.height / image.size.width)
        let turns = (rotation % 4 + 4) % 4
        pageSize = turns % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
        super.init(frame: .zero)
        addSubview(scroll)
        scroll.delegate = self
        scroll.addSubview(pageContainer)
        pageContainer.frame = CGRect(origin: .zero, size: pageSize)
        pageContainer.addSubview(paper)
        paper.bounds = CGRect(origin: .zero, size: size)
        paper.center = CGPoint(x: pageSize.width / 2, y: pageSize.height / 2)
        paper.transform = CGAffineTransform(rotationAngle: CGFloat(turns) * .pi / 2)
        paper.backgroundColor = .white
        let background = UIImageView(image: image)
        background.frame = CGRect(origin: .zero, size: size)
        paper.addSubview(background)
        canvas.frame = background.frame
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
        paper.addSubview(canvas)
        scroll.contentSize = pageSize
        picker.addObserver(canvas)
    }
    required init?(coder: NSCoder) { fatalError("Use init(image:canvas:rotation:)") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { picker.setVisible(true, forFirstResponder: canvas); canvas.becomeFirstResponder() }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        if previousSize != bounds.size {
            previousSize = bounds.size
            let fit = min(bounds.width / pageSize.width, bounds.height / pageSize.height) * 0.94
            scroll.minimumZoomScale = fit
            scroll.maximumZoomScale = max(fit * 5, 2)
            scroll.zoomScale = fit
        }
        scroll.contentInset = UIEdgeInsets(top: max(0, (bounds.height - scroll.contentSize.height) / 2), left: max(0, (bounds.width - scroll.contentSize.width) / 2), bottom: 0, right: 0)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { pageContainer }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { setNeedsLayout() }
}
