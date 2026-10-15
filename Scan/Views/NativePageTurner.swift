import SwiftUI
import UIKit

/// Uses UIKit's native page curl, with a scroll transition when Reduce Motion is enabled.
struct NativePageTurner: UIViewControllerRepresentable {
    let pages: [NotePage]
    @Binding var currentID: UUID
    let reduceMotion: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: reduceMotion ? .scroll : .pageCurl, navigationOrientation: .horizontal)
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.isDoubleSided = false
        if let page = pages.first(where: { $0.id == currentID }) { controller.setViewControllers([context.coordinator.controller(page)], direction: .forward, animated: false) }
        return controller
    }
    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.turning, let page = pages.first(where: { $0.id == currentID }) else { return }
        let visible = controller.viewControllers?.first as? PageImageController
        let revision = "\(page.rotation):\(page.drawingData.hashValue)"
        if visible?.pageID != page.id || visible?.revision != revision {
            let oldIndex = pages.firstIndex { $0.id == visible?.pageID } ?? 0
            let newIndex = pages.firstIndex { $0.id == page.id } ?? 0
            let animate = visible?.pageID != page.id && !reduceMotion
            context.coordinator.turning = animate
            controller.setViewControllers([context.coordinator.controller(page)], direction: newIndex >= oldIndex ? .forward : .reverse, animated: animate) { _ in
                context.coordinator.turning = false
            }
        }
    }
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: NativePageTurner
        var turning = false
        init(_ parent: NativePageTurner) { self.parent = parent }
        func controller(_ page: NotePage) -> PageImageController {
            PageImageController(pageID: page.id, revision: "\(page.rotation):\(page.drawingData.hashValue)", snapshot: PageSnapshot(page))
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? { neighbour(viewController, offset: -1) }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? { neighbour(viewController, offset: 1) }
        private func neighbour(_ controller: UIViewController, offset: Int) -> UIViewController? {
            guard let current = controller as? PageImageController,
                  let index = parent.pages.firstIndex(where: { $0.id == current.pageID }),
                  parent.pages.indices.contains(index + offset) else { return nil }
            return self.controller(parent.pages[index + offset])
        }
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) { turning = true }
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            turning = false
            if completed, let visible = pageViewController.viewControllers?.first as? PageImageController {
                parent.currentID = visible.pageID
                FolioStyle.haptic()
            }
        }
    }
}

final class PageImageController: UIViewController {
    let pageID: UUID
    let revision: String
    let snapshot: PageSnapshot
    private var renderingTask: Task<Void, Never>?
    init(pageID: UUID, revision: String, snapshot: PageSnapshot) {
        self.pageID = pageID; self.revision = revision; self.snapshot = snapshot
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(pageID:revision:snapshot:)") }
    override func loadView() {
        let zoom = ZoomingImageView()
        view = zoom
        let snapshot = snapshot
        renderingTask = Task {
            let image = await PageImageRenderer.shared.render(snapshot)
            guard !Task.isCancelled else { return }
            zoom.setImage(image.flatMap { UIImage(data: $0) })
        }
    }
    deinit { renderingTask?.cancel() }
}

actor PageImageRenderer {
    static let shared = PageImageRenderer()
    func render(_ snapshot: PageSnapshot) -> Data? { autoreleasepool { PageRendering.image(snapshot)?.jpegData(compressionQuality: 0.93) } }
}

final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var lastSize: CGSize = .zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .secondarySystemGroupedBackground
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        addSubview(imageView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        addGestureRecognizer(tap)
        accessibilityLabel = "Scanned page. Pinch or double tap to zoom."
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    func setImage(_ image: UIImage?) {
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image?.size ?? .zero)
        contentSize = image?.size ?? .zero
        lastSize = .zero
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
        if lastSize != bounds.size {
            lastSize = bounds.size
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height) * 0.95
            minimumZoomScale = fit
            maximumZoomScale = max(fit * 6, 1.5)
            zoomScale = fit
        }
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { setNeedsLayout() }
    @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.1 { setZoomScale(minimumZoomScale, animated: true) }
        else {
            let point = gesture.location(in: imageView)
            let scale = min(maximumZoomScale, minimumZoomScale * 2.5)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
