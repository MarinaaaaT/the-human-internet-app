//
//  VerifiedPhotoLinkTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// Pins the contract between this app and the website: the link the share
/// sheet copies has to resolve to the Next.js `/[photoId]` route, which looks
/// the photo up by its bare `photos.id`. A change on either side that breaks
/// that silently produces dead links in the wild.
struct VerifiedPhotoLinkTests {
    private func makePhoto(id: UUID) -> VerifiedPhoto {
        VerifiedPhoto(
            id: id,
            userID: UUID(),
            storagePath: "\(UUID().uuidString.lowercased())/\(id.uuidString.lowercased()).jpg",
            capturedAt: .now,
            verificationDeepLink: "thehumaninternet://photo/\(id.uuidString.lowercased())"
        )
    }

    @Test func sharedURLPointsAtTheWebVerificationRoute() throws {
        let id = UUID()
        let photo = makePhoto(id: id)
        let url = photo.verificationURL

        // Must be a real, tappable https URL — the display string alone has
        // no scheme and wouldn't linkify when pasted.
        #expect(url.scheme == "https")
        #expect(url.host() == "the-human-internet.com")

        // The path is the bare photo id, lowercased to match Postgres's
        // canonical uuid rendering. Swift's uuidString is uppercase.
        #expect(url.path() == "/\(id.uuidString.lowercased())")
        #expect(url.path() != "/\(id.uuidString)")
    }

    @Test func sharedURLIsTheDisplayLinkPlusScheme() {
        let photo = makePhoto(id: UUID())
        #expect(photo.verificationURL.absoluteString == "https://\(photo.verificationLink)")
    }

    @Test func sharedURLIsNotTheDeepLink() {
        let photo = makePhoto(id: UUID())
        // The deep link only resolves for people who already have the app;
        // the whole point of the shared link is that it works signed out.
        #expect(photo.verificationURL.absoluteString != photo.verificationDeepLink)
        #expect(photo.verificationURL.scheme != "thehumaninternet")
    }
}
