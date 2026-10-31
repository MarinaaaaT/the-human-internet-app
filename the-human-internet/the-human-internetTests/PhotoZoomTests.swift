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

    private func leadingInset(_ length: CGFloat, _ viewport: CGFloat, _ center: CGFloat, resting: CGFloat) -> CGFloat {
        ZoomingScrollView.leadingInset(length: length, viewport: viewport, restingCenter: center, restingLength: resting)
    }

    @Test func atOneTimesThePhotoRestsInItsCard() {
        #expect(leadingInset(card.width, screen.width, card.midX, resting: card.width) == card.minX)
        #expect(leadingInset(card.height, screen.height, card.midY, resting: card.height) == card.minY)
    }

    @Test func zoomingGrowsThePhotoOutOfItsCard() {
        let height = card.height * 1.2
        #expect(leadingInset(height, screen.height, card.midY, resting: card.height) == card.midY - height / 2)
    }

    /// Near an edge, it pushes back in rather than running off the screen
    /// while there's still room for all of it.
    @Test func aPhotoThatStillFitsStaysOnScreen() {
        let small = CGRect(x: 10, y: 0, width: 100, height: 100)
        let width: CGFloat = 140
        #expect(leadingInset(width, screen.width, small.midX, resting: small.width) == 0)
        let right = small.offsetBy(dx: screen.width - small.maxX - 10, dy: 0)
        #expect(leadingInset(width, screen.width, right.midX, resting: right.width) == screen.width - width)
    }

    @Test func aPhotoBiggerThanTheScreenPansEdgeToEdge() {
        #expect(leadingInset(card.width * 2, screen.width, card.midX, resting: card.width) == 0)
        #expect(leadingInset(card.height * 2, screen.height, card.midY, resting: card.height) == 0)
    }

    /// An iPad Pro 13-inch: the 3:4 photo, full width, is taller than the
    /// space under the Close bar and runs off the bottom of the screen. At 1x
    /// it stays under the header, rather than being pulled up over it.
    @Test func aPhotoRunningOffTheScreenRestsInItsCard() {
        let viewport: CGFloat = 1276
        let tall = CGRect(x: 24, y: 196, width: 984, height: 1312)
        #expect(leadingInset(tall.height, viewport, tall.midY, resting: tall.height) == tall.minY)
        // Growing, it moves smoothly toward the top, and is at it by 2x.
        let slightly = leadingInset(tall.height + 2, viewport, tall.midY, resting: tall.height)
        #expect(slightly < tall.minY && slightly > tall.minY - 4)
        #expect(leadingInset(tall.height * 2, viewport, tall.midY, resting: tall.height) == 0)
    }

    /// Scrolled part way above the screen, it stays where the page put it.
    @Test func aPhotoScrolledPartlyOffScreenRestsInItsCard() {
        let scrolled = card.offsetBy(dx: 0, dy: -200)
        #expect(leadingInset(scrolled.height, screen.height, scrolled.midY, resting: scrolled.height) == scrolled.minY)
        #expect(leadingInset(scrolled.height * 2, screen.height, scrolled.midY, resting: scrolled.height) == 0)
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
