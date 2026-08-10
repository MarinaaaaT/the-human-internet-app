//
//  VerifiedPhotoLinkTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// Pins the contract between this app and the website: the link the share
/// sheet copies has to resolve to the Next.js `/[photoId]` route, which looks
/// the photo up by its `short_code` (falling back to the bare `photos.id`
/// for links shared before short codes existed). A change on either side
/// that breaks that silently produces dead links in the wild.
struct VerifiedPhotoLinkTests {
    private func makePhoto(id: UUID, shortCode: String = "aB3xK9mP") -> VerifiedPhoto {
        VerifiedPhoto(
            id: id,
            userID: UUID(),
            storagePath: "\(UUID().uuidString.lowercased())/\(id.uuidString.lowercased()).jpg",
            capturedAt: .now,
            verificationDeepLink: "thehumaninternet://photo/\(id.uuidString.lowercased())",
            shortCode: shortCode
        )
    }

    @Test func sharedURLPointsAtTheWebVerificationRoute() throws {
        let photo = makePhoto(id: UUID(), shortCode: "aB3xK9mP")
        let url = photo.verificationURL

        // Must be a real, tappable https URL — the display string alone has
        // no scheme and wouldn't linkify when pasted.
        #expect(url.scheme == "https")
        #expect(url.host() == "the-human-internet.com")

        // The path is the short code, not the id — much shorter, and still
        // collision-free (see `VerifiedPhoto.generateShortCode`).
        #expect(url.path() == "/aB3xK9mP")
    }

    @Test func generatedShortCodeIsEightBase58Characters() {
        let code = VerifiedPhoto.generateShortCode()
        #expect(code.count == 8)
        // Base58 (Bitcoin alphabet): no 0/O/I/l, avoiding visual ambiguity.
        let disallowed = Set("0OIl")
        #expect(code.allSatisfy { $0.isLetter || $0.isNumber })
        #expect(code.allSatisfy { !disallowed.contains($0) })
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
