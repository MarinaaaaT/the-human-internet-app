//
//  PhotoZoomTests.swift
//  the-human-internetTests
//

import CoreGraphics
import Testing

@testable import the_human_internet

/// Photo detail zooms the open photo with a pinch, or with a double-tap that
/// zooms in around the tapped point.
@MainActor
struct PhotoZoomTests {
    private let size = CGSize(width: 300, height: 400)

    @Test func doubleTapZoomsInAroundTheTappedPoint() {
        let point = CGPoint(x: 90, y: 250)
        let rect = ZoomingScrollView.doubleTapZoomRect(centeredOn: point, in: size)
        #expect(rect.midX == point.x)
        #expect(rect.midY == point.y)
    }

    @Test func doubleTapZoomsToItsScaleWithoutDistorting() {
        let rect = ZoomingScrollView.doubleTapZoomRect(centeredOn: CGPoint(x: 150, y: 200), in: size)
        #expect(rect.width * ZoomingScrollView.doubleTapZoomScale == size.width)
        #expect(rect.height * ZoomingScrollView.doubleTapZoomScale == size.height)
    }

    /// A double-tap past the pinch limit would be clamped to it, so the two
    /// gestures would disagree about how far in the photo goes.
    @Test func doubleTapStaysWithinThePinchLimit() {
        #expect(ZoomingScrollView.doubleTapZoomScale > 1)
        #expect(ZoomingScrollView.doubleTapZoomScale <= ZoomingScrollView.maximumZoomScale)
    }
}
