//
//  PhotoPagerTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// Photo detail pages through the whole grid. Deleting a photo keeps the
/// pager open on a neighbour rather than leaving it, and only the photos
/// next to the open one hold a full-resolution image.
struct PhotoPagerTests {
    private let photos = (1...3).map { n in
        VerifiedPhoto(id: UUID(), userID: UUID(), storagePath: "test/\(n).jpg", capturedAt: .now, verificationDeepLink: "thehumaninternet://photo/test", shortCode: "testcod\(n)")
    }

    @Test func deletingLandsOnThePhotoASwipeLeftWouldReach() {
        #expect(PhotoDetailView.photoToShow(afterDeleting: photos[0].id, from: photos) == photos[1])
        #expect(PhotoDetailView.photoToShow(afterDeleting: photos[1].id, from: photos) == photos[2])
    }

    @Test func deletingTheLastPhotoStepsBack() {
        #expect(PhotoDetailView.photoToShow(afterDeleting: photos[2].id, from: photos) == photos[1])
    }

    @Test func deletingTheOnlyPhotoLeavesNothingToShow() {
        #expect(PhotoDetailView.photoToShow(afterDeleting: photos[0].id, from: [photos[0]]) == nil)
    }

    @Test func onlyTheOpenPhotoAndItsNeighboursLoad() {
        #expect(PhotoDetailView.isWithinPreloadWindow(4, of: 5))
        #expect(PhotoDetailView.isWithinPreloadWindow(5, of: 5))
        #expect(PhotoDetailView.isWithinPreloadWindow(6, of: 5))
        #expect(!PhotoDetailView.isWithinPreloadWindow(3, of: 5))
        #expect(!PhotoDetailView.isWithinPreloadWindow(7, of: 5))
    }
}
