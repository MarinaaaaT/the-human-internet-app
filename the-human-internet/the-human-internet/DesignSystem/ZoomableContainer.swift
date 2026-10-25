//
//  ZoomableContainer.swift
//  the-human-internet
//

import SwiftUI
import UIKit

extension View {
    /// Lets a zoomable `RemotePhotoImage` inside this view zoom across this
    /// view's whole frame, safe areas included — the photo takes over the
    /// screen, the way it does in Photos, rather than zooming inside its card.
    ///
    /// The layer draws the photo itself, behind this view's content, starting
    /// from exactly where the `RemotePhotoImage` was laid out; that view keeps
    /// the photo's place in the layout and draws nothing. Content over the
    /// photo's path should `fadesWhilePhotoZoomed(isZoomed)`.
    func photoZoomLayer(isZoomed: Binding<Bool>, cornerRadius: CGFloat) -> some View {
        environment(\.isInPhotoZoomLayer, true)
            .backgroundPreferenceValue(ZoomablePhotoPreferenceKey.self) { photo in
                GeometryReader { proxy in
                    if let photo {
                        ZoomableContainer(
                            restingRect: proxy[photo.restingBounds],
                            cornerRadius: cornerRadius,
                            onZoomChange: { isZoomed.wrappedValue = $0 }
                        ) {
                            LoadedPhoto(image: photo.image, isProvisional: photo.isProvisional, markColor: photo.markColor)
                        }
                        // Gone while zoomed — swiped away, or swapped for its
                        // watermarked version — leaves nothing zoomed.
                        .onDisappear { isZoomed.wrappedValue = false }
                    }
                }
                .ignoresSafeArea()
            }
    }

    /// Fades out the screen around a zoomed photo, and lets touches through
    /// to it, until the photo is back at 1x.
    func fadesWhilePhotoZoomed(_ isZoomed: Bool) -> some View {
        opacity(isZoomed ? 0 : 1)
            .allowsHitTesting(!isZoomed)
            .accessibilityHidden(isZoomed)
            .animation(.brandBase, value: isZoomed)
    }
}

extension EnvironmentValues {
    /// Set by `photoZoomLayer`. A zoomable `RemotePhotoImage` outside one
    /// draws its photo itself and doesn't zoom.
    @Entry var isInPhotoZoomLayer = false
}

/// A zoomable `RemotePhotoImage`'s loaded photo, handed up to the enclosing
/// `photoZoomLayer` to draw.
struct ZoomablePhoto {
    let image: UIImage
    let isProvisional: Bool
    let markColor: PhotoWatermarker.MarkColor
    /// Where the `RemotePhotoImage` was laid out — where the photo rests at 1x.
    let restingBounds: Anchor<CGRect>
}

struct ZoomablePhotoPreferenceKey: PreferenceKey {
    static let defaultValue: ZoomablePhoto? = nil

    static func reduce(value: inout ZoomablePhoto?, nextValue: () -> ZoomablePhoto?) {
        value = value ?? nextValue()
    }
}

/// The pinch and double-tap zoom behind `photoZoomLayer`.
///
/// A `UIScrollView` rather than SwiftUI gestures, for two things SwiftUI has
/// no equivalent of: the system's own zoom physics (deceleration, bouncing
/// back from past the limits), and nesting inside photo detail's paging
/// `TabView` — itself a scroll view — so that at 1x a swipe still pages, and
/// once zoomed a drag pans the photo until it reaches an edge, then pages.
struct ZoomableContainer<Content: View>: UIViewRepresentable {
    let restingRect: CGRect
    let cornerRadius: CGFloat
    let onZoomChange: (Bool) -> Void
    private let content: Content

    init(
        restingRect: CGRect,
        cornerRadius: CGFloat,
        onZoomChange: @escaping (Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.restingRect = restingRect
        self.cornerRadius = cornerRadius
        self.onZoomChange = onZoomChange
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
        scrollView.onZoomChange = onZoomChange
        scrollView.cornerRadius = cornerRadius
        scrollView.restingRect = restingRect
    }
}

/// The UIKit half of `ZoomableContainer`: a scroll view as big as the screen,
/// zooming one view that rests at `restingRect` at 1x.
final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    /// About 1:1 with the pixels of a 12MP capture shown full width on a phone.
    static let maximumZoomScale: CGFloat = 4
    static let doubleTapZoomScale: CGFloat = 2.5

    /// Where the zoomed view sits at 1x, in this view's own frame. A change
    /// while zoomed waits until the zoom is back at 1x, so nothing jumps
    /// under the user's fingers.
    var restingRect: CGRect = .zero {
        didSet { if restingRect != oldValue { settleIfUnzoomed() } }
    }
    /// The zoomed view's corner radius on screen, held steady at any zoom.
    var cornerRadius: CGFloat = 0 {
        didSet { updateCornerRadius() }
    }
    var onZoomChange: ((Bool) -> Void)?

    private let zoomedView: UIView
    /// The `restingRect` the zoomed view is currently laid out for.
    private var settledRect: CGRect?
    private var isZoomed = false
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
        zoomedView.layer.masksToBounds = true
        zoomedView.layer.cornerCurve = .continuous
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
        if isZoomed {
            updateInsets()
        } else {
            settledRect = nil
            settleIfUnzoomed()
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomedView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateInsets()
        updateCornerRadius()
        let zoomed = zoomScale > minimumZoomScale
        guard zoomed != isZoomed else { return }
        isZoomed = zoomed
        onZoomChange?(zoomed)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        settleIfUnzoomed()
    }

    /// Lays the zoomed view out at `restingRect`, at 1x — skipped mid-zoom,
    /// and caught up on by `scrollViewDidEndZooming` once back at 1x.
    private func settleIfUnzoomed() {
        guard !isZoomed, !isZooming, !isZoomBouncing, settledRect != restingRect else { return }
        settledRect = restingRect
        zoomScale = minimumZoomScale
        zoomedView.frame = CGRect(origin: .zero, size: restingRect.size)
        contentSize = restingRect.size
        updateInsets()
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        updateCornerRadius()
    }

    /// Insets that hold the zoomed view where `leadingInset` puts it while
    /// it's smaller than the screen, and let it pan edge to edge once larger.
    private func updateInsets() {
        let rest = settledRect ?? restingRect
        let size = zoomedView.frame.size
        let left = Self.leadingInset(length: size.width, viewport: bounds.width, restingCenter: rest.midX)
        let top = Self.leadingInset(length: size.height, viewport: bounds.height, restingCenter: rest.midY)
        contentInset = UIEdgeInsets(
            top: top,
            left: left,
            bottom: max(0, bounds.height - size.height - top),
            right: max(0, bounds.width - size.width - left)
        )
    }

    private func updateCornerRadius() {
        zoomedView.layer.cornerRadius = cornerRadius / zoomScale
    }

    /// Where content of `length` starts along one axis of the `viewport`:
    /// centred on where it rests at 1x, so it grows out from its card; kept
    /// inside the viewport once that would run it off an edge; and 0 once
    /// it's longer than the viewport, so every part of it can be panned to.
    static func leadingInset(length: CGFloat, viewport: CGFloat, restingCenter: CGFloat) -> CGFloat {
        min(max(restingCenter - length / 2, 0), max(viewport - length, 0))
    }

    /// Zooms in around the tapped point, or back out to 1x if already zoomed.
    /// Like a pinch, this is the photo answering the user's own hand, so it
    /// moves with the system's zoom animation — except under Reduce Motion,
    /// where it jumps.
    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let animated = !UIAccessibility.isReduceMotionEnabled
        if isZoomed {
            setZoomScale(minimumZoomScale, animated: animated)
            return
        }
        let point = recognizer.location(in: zoomedView)
        // At 1x the rest of the screen is the page around the photo.
        guard zoomedView.bounds.contains(point) else { return }
        zoom(to: Self.doubleTapZoomRect(centeredOn: point, viewport: bounds.size), animated: animated)
    }

    /// The region of the zoomed view, in its own unzoomed coordinates, that
    /// fills the `viewport` at `doubleTapZoomScale`. `zoom(to:)` keeps it
    /// inside the photo when the tap was near an edge.
    static func doubleTapZoomRect(centeredOn point: CGPoint, viewport: CGSize) -> CGRect {
        let size = CGSize(width: viewport.width / doubleTapZoomScale, height: viewport.height / doubleTapZoomScale)
        return CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
