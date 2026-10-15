import SwiftUI
import UIKit

/// Uses UIKit's native page curl, with a scroll transition when Reduce Motion is enabled.
struct NativePageTurner: UIViewControllerRepresentable {
    let entries: [BookEntry]
    @Binding var currentID: String
    let reduceMotion: Bool
    var paper: String = "system"
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: reduceMotion ? .scroll : .pageCurl, navigationOrientation: .horizontal)
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.isDoubleSided = false
        if let entry = entries.first(where: { $0.id == currentID }) { controller.setViewControllers([context.coordinator.controller(entry)], direction: .forward, animated: false) }
        return controller
    }
    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.turning, let entry = entries.first(where: { $0.id == currentID }) else { return }
        let visible = controller.viewControllers?.first as? ReaderEntryController
        let revision: String
        switch entry { case .page(let page): revision = page.visualVersion.uuidString; case .section(let section): revision = section.modifiedAt.description }
        if visible?.entryID != entry.id || visible?.revision != revision {
            let oldIndex = entries.firstIndex { $0.id == visible?.entryID } ?? 0
            let newIndex = entries.firstIndex { $0.id == entry.id } ?? 0
            let animate = visible?.entryID != entry.id && !reduceMotion
            context.coordinator.turning = animate
            controller.setViewControllers([context.coordinator.controller(entry)], direction: newIndex >= oldIndex ? .forward : .reverse, animated: animate) { _ in
                context.coordinator.turning = false
            }
        }
    }
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: NativePageTurner
        var turning = false
        init(_ parent: NativePageTurner) { self.parent = parent }
        func controller(_ entry: BookEntry) -> ReaderEntryController {
            switch entry {
            case .page(let page): PageImageController(pageID: page.id, revision: page.visualVersion.uuidString, snapshot: PageSnapshot(page), paper: parent.paper)
            case .section(let section): DividerImageController(section: section)
            }
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? { neighbour(viewController, offset: -1) }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? { neighbour(viewController, offset: 1) }
        private func neighbour(_ controller: UIViewController, offset: Int) -> UIViewController? {
            guard let current = controller as? ReaderEntryController,
                  let index = parent.entries.firstIndex(where: { $0.id == current.entryID }),
                  parent.entries.indices.contains(index + offset) else { return nil }
            return self.controller(parent.entries[index + offset])
        }
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) { turning = true }
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            turning = false
            if completed, let visible = pageViewController.viewControllers?.first as? ReaderEntryController {
                parent.currentID = visible.entryID
                FolioStyle.haptic()
            }
        }
    }
}

class ReaderEntryController: UIViewController {
    let entryID: String
    let revision: String
    init(entryID: String, revision: String) {
        self.entryID = entryID; self.revision = revision
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(entryID:revision:)") }
}

final class DividerImageController: ReaderEntryController {
    let section: BookSection
    init(section: BookSection) {
        self.section = section
        super.init(entryID: "section:" + section.id.uuidString, revision: section.modifiedAt.description)
    }
    required init?(coder: NSCoder) { fatalError("Use init(section:)") }
    override func loadView() {
        view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        let host = UIHostingController(rootView: DividerReaderPage(section: section))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}

struct DividerReaderPage: View {
    let section: BookSection
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: section.symbol).font(.system(size: 54, weight: .light))
                    .frame(width: 108, height: 108)
                    .background(FolioStyle.color(section.colorName).opacity(0.15), in: RoundedRectangle(cornerRadius: 28))
                Text(section.title).font(.system(size: 36, weight: .medium, design: .serif)).multilineTextAlignment(.center)
                Rectangle().fill(FolioStyle.color(section.colorName)).frame(width: 80, height: 4)
                Spacer()
            }
            .foregroundStyle(FolioStyle.color(section.colorName))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }.accessibilityElement(children: .combine).accessibilityLabel("Divider, \(section.title)")
    }
}

final class PageImageController: ReaderEntryController {
    let pageID: UUID
    let snapshot: PageSnapshot
    let paper: String
    private var renderingTask: Task<Void, Never>?
    init(pageID: UUID, revision: String, snapshot: PageSnapshot, paper: String) {
        self.pageID = pageID; self.snapshot = snapshot; self.paper = paper
        super.init(entryID: "page:" + pageID.uuidString, revision: revision)
    }
    required init?(coder: NSCoder) { fatalError("Use init(pageID:revision:snapshot:)") }
    override func loadView() {
        let zoom = ZoomingImageView()
        zoom.backgroundColor = paper == "warm" ? UIColor(red: 0.94, green: 0.91, blue: 0.84, alpha: 1) : paper == "dark" ? UIColor(white: 0.1, alpha: 1) : .secondarySystemGroupedBackground
        view = zoom
        let progress = UIActivityIndicatorView(style: .medium)
        progress.translatesAutoresizingMaskIntoConstraints = false
        zoom.addSubview(progress)
        NSLayoutConstraint.activate([
            progress.centerXAnchor.constraint(equalTo: zoom.frameLayoutGuide.centerXAnchor),
            progress.centerYAnchor.constraint(equalTo: zoom.frameLayoutGuide.centerYAnchor)
        ])
        progress.startAnimating()
        let snapshot = snapshot
        renderingTask = Task {
            let image = await PageImageRenderer.shared.render(snapshot)
            guard !Task.isCancelled else { return }
            progress.removeFromSuperview()
            if let image = image.flatMap({ UIImage(data: $0) }) { zoom.setImage(image) }
            else {
                let message = UILabel()
                message.text = "This image couldn’t load. Close and reopen the page to try again."
                message.numberOfLines = 0; message.textAlignment = .center
                message.textColor = .secondaryLabel
                message.translatesAutoresizingMaskIntoConstraints = false
                zoom.addSubview(message)
                NSLayoutConstraint.activate([
                    message.centerYAnchor.constraint(equalTo: zoom.frameLayoutGuide.centerYAnchor),
                    message.leadingAnchor.constraint(equalTo: zoom.frameLayoutGuide.leadingAnchor, constant: 24),
                    message.trailingAnchor.constraint(equalTo: zoom.frameLayoutGuide.trailingAnchor, constant: -24)
                ])
            }
        }
    }
    deinit { renderingTask?.cancel() }
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
        contentInsetAdjustmentBehavior = .never
        imageView.isAccessibilityElement = true
        imageView.accessibilityIdentifier = "reader.image"
        imageView.accessibilityLabel = "Original scanned page"
        addSubview(imageView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        addGestureRecognizer(tap)
        accessibilityLabel = "Scanned page. Pinch or double tap to zoom."
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    func setImage(_ image: UIImage?) {
        zoomScale = 1
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
