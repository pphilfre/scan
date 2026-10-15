import SwiftUI
import SwiftData
import PencilKit

struct AnnotationEditor: View {
    let page: NotePage
    let importer: ImportCoordinator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryActions.self) private var actions
    @Environment(AccessController.self) private var access
    @State private var canvas = PKCanvasView()
    @State private var image: UIImage?
    var body: some View {
        NavigationStack {
            Group {
                if let image { InkCanvas(image: image, canvas: canvas, rotation: page.rotation, adjustments: ImageAdjustments(data: page.enhancementData)) }
                else { ProgressView("Opening page…") }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Annotate").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard access.canRead(page) else { return }
                        actions.edit([page], in: context, name: "Annotate page") { page.drawingData = canvas.drawing.dataRepresentation() }
                        dismiss()
                    }.fontWeight(.semibold).disabled(image == nil)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { canvas.undoManager?.undo() }
                    Spacer()
                    Menu("Tools", systemImage: "pencil.tip") {
                        Button("Pen", systemImage: "pencil.tip") { canvas.isRulerActive = false; canvas.tool = PKInkingTool(.pen, color: .black, width: 3) }
                        Button("Highlighter", systemImage: "highlighter") { canvas.isRulerActive = false; canvas.tool = PKInkingTool(.marker, color: .systemYellow, width: 26) }
                        Button("Underline", systemImage: "underline") { canvas.tool = PKInkingTool(.pen, color: .black, width: 2); canvas.isRulerActive = true }
                        Button("Eraser", systemImage: "eraser") { canvas.tool = PKEraserTool(.vector) }
                    }
                    Spacer()
                    Button("Redo", systemImage: "arrow.uturn.forward") { canvas.undoManager?.redo() }
                }
            }
            .task {
                canvas.drawing = (try? PKDrawing(data: page.drawingData)) ?? PKDrawing()
                let data = await PageImageRenderer.shared.annotationBase(PageSnapshot(page))
                if !Task.isCancelled { image = data.flatMap { UIImage(data: $0) } }
            }
        }.interactiveDismissDisabled().modifier(PageProtection(page: page))
    }
}

struct InkCanvas: UIViewRepresentable {
    let image: UIImage
    let canvas: PKCanvasView
    let rotation: Int
    let adjustments: ImageAdjustments
    func makeUIView(context: Context) -> InkSurface { InkSurface(image: image, canvas: canvas, rotation: rotation, adjustments: adjustments) }
    func updateUIView(_ view: InkSurface, context: Context) {}
}

final class InkSurface: UIView, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let paper = UIView()
    private let cropContainer = UIView()
    private let pageContainer = UIView()
    private let canvas: PKCanvasView
    private let picker = PKToolPicker()
    private let pageSize: CGSize
    private var previousSize: CGSize = .zero
    init(image: UIImage, canvas: PKCanvasView, rotation: Int, adjustments: ImageAdjustments) {
        self.canvas = canvas
        let size = CGSize(width: 1000, height: 1000 * image.size.height / image.size.width)
        let turns = (rotation % 4 + 4) % 4
        let normalized = adjustments.crop.clamped
        let crop = CGRect(x: normalized.x * size.width, y: normalized.y * size.height, width: normalized.width * size.width, height: normalized.height * size.height)
        pageSize = turns % 2 == 0 ? crop.size : CGSize(width: crop.height, height: crop.width)
        super.init(frame: .zero)
        addSubview(scroll)
        scroll.delegate = self
        scroll.addSubview(pageContainer)
        pageContainer.frame = CGRect(origin: .zero, size: pageSize)
        pageContainer.addSubview(cropContainer)
        cropContainer.bounds = CGRect(origin: .zero, size: crop.size)
        cropContainer.center = CGPoint(x: pageSize.width / 2, y: pageSize.height / 2)
        cropContainer.transform = CGAffineTransform(rotationAngle: CGFloat(turns) * .pi / 2)
        cropContainer.clipsToBounds = true
        cropContainer.addSubview(paper)
        paper.bounds = CGRect(origin: .zero, size: size)
        paper.center = CGPoint(x: size.width / 2 - crop.minX, y: size.height / 2 - crop.minY)
        paper.transform = CGAffineTransform(rotationAngle: CGFloat(adjustments.straighten) * .pi / 180)
        paper.backgroundColor = .white
        let background = UIImageView(image: image)
        background.frame = CGRect(origin: .zero, size: size)
        paper.addSubview(background)
        canvas.frame = background.frame
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
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
