import UIKit

/// Cover every app window, including presented sheets, before a switcher snapshot.
@MainActor enum PrivacyShield {
    private static let tag = 864201
    static func setVisible(_ visible: Bool) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                if visible {
                    guard window.viewWithTag(tag) == nil else { continue }
                    let cover = UIView(frame: window.bounds)
                    cover.tag = tag; cover.backgroundColor = .systemGroupedBackground
                    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    let icon = UIImageView(image: UIImage(systemName: "book.closed"))
                    icon.tintColor = .secondaryLabel; icon.contentMode = .scaleAspectFit
                    icon.frame = CGRect(x: cover.bounds.midX - 22, y: cover.bounds.midY - 22, width: 44, height: 44)
                    icon.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
                    cover.addSubview(icon); window.addSubview(cover)
                } else { window.viewWithTag(tag)?.removeFromSuperview() }
            }
        }
    }
}
