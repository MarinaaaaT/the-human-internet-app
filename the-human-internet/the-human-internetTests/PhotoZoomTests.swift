//
//  PhotoZoomTests.swift
//  the-human-internetTests
//

import CoreGraphics
import Testing

@testable import the_human_internet

/// Photo detail and the verification page zoom their photo across the whole
/// screen: it grows out of its card, and once bigger than the screen it can
/// be panned edge to edge.
@MainActor
struct PhotoZoomTests {
    /// An iPhone 16 Pro, and a 3:4 photo resting full width below the nav bar.
    private let screen = CGSize(width: 402, height: 874)
    private let card = CGRect(x: 24, y: 118, width: 354, height: 472)

    private func leadingInset(_ length: CGFloat, _ viewport: CGFloat, _ center: CGFloat) -> CGFloat {
        ZoomingScrollView.leadingInset(length: length, viewport: viewport, restingCenter: center)
    }

    @Test func atOneTimesThePhotoRestsInItsCard() {
        #expect(leadingInset(card.width, screen.width, card.midX) == card.minX)
        #expect(leadingInset(card.height, screen.height, card.midY) == card.minY)
    }

    @Test func zoomingGrowsThePhotoOutOfItsCard() {
        let height = card.height * 1.2
        #expect(leadingInset(height, screen.height, card.midY) == card.midY - height / 2)
    }

    /// Near an edge, it pushes back in rather than running off the screen
    /// while there's still room for all of it.
    @Test func aPhotoThatStillFitsStaysOnScreen() {
        let width = card.width * 1.1
        #expect(leadingInset(width, screen.width, 60) == 0)
        #expect(leadingInset(width, screen.width, screen.width - 60) == screen.width - width)
    }

    @Test func aPhotoBiggerThanTheScreenPansEdgeToEdge() {
        #expect(leadingInset(card.width * 2, screen.width, card.midX) == 0)
        #expect(leadingInset(card.height * 2, screen.height, card.midY) == 0)
    }

    @Test func doubleTapZoomsInAroundTheTappedPoint() {
        let point = CGPoint(x: 90, y: 250)
        let rect = ZoomingScrollView.doubleTapZoomRect(centeredOn: point, viewport: screen)
        #expect(rect.midX == point.x)
        #expect(rect.midY == point.y)
    }

    /// The rect fills the screen at exactly the double-tap scale, whatever
    /// size the photo's card is.
    @Test func doubleTapZoomsToItsScale() {
        let rect = ZoomingScrollView.doubleTapZoomRect(centeredOn: CGPoint(x: 150, y: 200), viewport: screen)
        #expect(rect.width * ZoomingScrollView.doubleTapZoomScale == screen.width)
        #expect(rect.height * ZoomingScrollView.doubleTapZoomScale == screen.height)
    }

    /// A double-tap past the pinch limit would be clamped to it, so the two
    /// gestures would disagree about how far in the photo goes.
    @Test func doubleTapStaysWithinThePinchLimit() {
        #expect(ZoomingScrollView.doubleTapZoomScale > 1)
        #expect(ZoomingScrollView.doubleTapZoomScale <= ZoomingScrollView.maximumZoomScale)
    }
}
