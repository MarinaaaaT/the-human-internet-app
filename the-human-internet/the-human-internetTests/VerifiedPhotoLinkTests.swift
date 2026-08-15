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

    // MARK: - Derived formats
    //
    // The deriving initializer is what `PhotoRepository.upload` and
    // `PhotoUploadQueue`'s enqueue/resume paths all go through, so pinning it
    // here pins all three at once. Both formats are contracts that outlive any
    // one build: the storage path is matched by a Storage RLS policy, and the
    // deep link is baked into links already shared in the wild.

    @Test func derivedStoragePathIsUserThenPhotoLowercasedJPEG() {
        let userID = UUID()
        let photoID = UUID()
        let photo = VerifiedPhoto(id: photoID, userID: userID, capturedAt: .now, shortCode: "aB3xK9mP")

        #expect(photo.storagePath == "\(userID.uuidString.lowercased())/\(photoID.uuidString.lowercased()).jpg")
        // Lowercase matters: Postgres renders `auth.uid()::text` lowercase,
        // and a case-sensitive comparison in the original RLS policy silently
        // rejected every upload.
        #expect(photo.storagePath == photo.storagePath.lowercased())
    }

    @Test func derivedDeepLinkUsesTheRegisteredSchemeAndPhotoHost() throws {
        let photoID = UUID()
        let photo = VerifiedPhoto(id: photoID, userID: UUID(), capturedAt: .now, shortCode: "aB3xK9mP")

        let url = try #require(URL(string: photo.verificationDeepLink))
        #expect(url.scheme == "thehumaninternet")
        #expect(url.host == "photo")
        // `RootView.handle(url:)` parses the id back out of the last path
        // component — a format change that breaks this breaks every deep
        // link already shared.
        #expect(UUID(uuidString: url.lastPathComponent) == photoID)
    }

    @Test func derivedInitAgreesWithTheStandaloneFormatHelpers() {
        let userID = UUID()
        let photoID = UUID()
        let photo = VerifiedPhoto(id: photoID, userID: userID, capturedAt: .now, shortCode: "aB3xK9mP")

        #expect(photo.storagePath == VerifiedPhoto.storagePath(userID: userID, photoID: photoID))
        #expect(photo.verificationDeepLink == VerifiedPhoto.deepLink(photoID: photoID))
    }

    @Test func derivedInitPreservesIdentityFields() {
        let userID = UUID()
        let photoID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let photo = VerifiedPhoto(id: photoID, userID: userID, capturedAt: capturedAt, shortCode: "aB3xK9mP")

        #expect(photo.id == photoID)
        #expect(photo.userID == userID)
        #expect(photo.capturedAt == capturedAt)
        // Generated once at enqueue time and carried through retries unchanged.
        #expect(photo.shortCode == "aB3xK9mP")
    }
}
