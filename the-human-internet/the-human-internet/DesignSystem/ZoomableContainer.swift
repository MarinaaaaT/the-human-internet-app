//
//  ZoomableContainer.swift
//  the-human-internet
//

import SwiftUI
import UIKit

/// Pinch and double-tap zoom for `RemotePhotoImage(isZoomable:)`.
///
/// A `UIScrollView` rather than SwiftUI gestures, for two things SwiftUI has
/// no equivalent of: the system's own zoom physics (deceleration, bouncing
/// back from past the limits), and nesting inside photo detail's paging
/// `TabView` — itself a scroll view — so that at 1x a swipe still pages, and
/// once zoomed a drag pans the photo until it reaches an edge, then pages.
///
/// The caller sizes this to the content's own aspect ratio, so the content
/// fills it exactly at 1x and there's never empty space to pan into.
struct ZoomableContainer<Content: View>: UIViewRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        // Zooming scales the hosted view far past the screen edges; left on,
        // the safe area it then overlaps would re-lay its content out mid-pinch.
        host.safeAreaRegions = []
        return host
    }

    func makeUIView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView(zoomedView: context.coordinator.view)
    }

    func updateUIView(_ scrollView: ZoomingScrollView, context: Context) {
        context.coordinator.rootView = content
    }
}

/// The UIKit half of `ZoomableContainer`: a scroll view whose only job is to
/// zoom one view that exactly fills it at 1x.
final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    /// About 1:1 with the pixels of a 12MP capture shown full width on a phone.
    static let maximumZoomScale: CGFloat = 4
    static let doubleTapZoomScale: CGFloat = 2.5

    private let zoomedView: UIView
    private var laidOutSize: CGSize = .zero

    init(zoomedView: UIView) {
        self.zoomedView = zoomedView
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = Self.maximumZoomScale
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        addSubview(zoomedView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        // A new size starts back at 1x: the zoomed view's frame can only be
        // set while it has no zoom transform on it.
        zoomScale = minimumZoomScale
        zoomedView.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomedView
    }

    /// Pinching below 1x — only mid-gesture, before it bounces back — makes
    /// the content smaller than its frame. Centres it there instead of
    /// leaving it pinned to the top-leading corner.
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    /// Zooms in around the tapped point, or back out to 1x if already zoomed.
    /// Like a pinch, this is the photo answering the user's own hand, so it
    /// moves with the system's zoom animation — except under Reduce Motion,
    /// where it jumps.
    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let animated = !UIAccessibility.isReduceMotionEnabled
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: animated)
        } else {
            let point = recognizer.location(in: zoomedView)
            zoom(to: Self.doubleTapZoomRect(centeredOn: point, in: zoomedView.bounds.size), animated: animated)
        }
    }

    /// The region of the content, in its own unzoomed coordinates, that
    /// fills the frame at `doubleTapZoomScale`. `zoom(to:)` keeps it inside
    /// the content when the tap was near an edge.
    static func doubleTapZoomRect(centeredOn point: CGPoint, in size: CGSize) -> CGRect {
        let zoomedSize = CGSize(width: size.width / doubleTapZoomScale, height: size.height / doubleTapZoomScale)
        return CGRect(
            x: point.x - zoomedSize.width / 2,
            y: point.y - zoomedSize.height / 2,
            width: zoomedSize.width,
            height: zoomedSize.height
        )
    }
}
