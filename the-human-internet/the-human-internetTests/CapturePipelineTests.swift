//
//  CapturePipelineTests.swift
//  the-human-internetTests
//

import Foundation
import Testing
import UIKit

@testable import the_human_internet

/// Pins this app's half of the server-side watermarking contract with the
/// backend repo — `sign-photo` (headers, originals bucket and path) and the
/// signing Lambda's `watermark.rs` (mark geometry). Nothing fails to compile
/// when either side drifts: a wrong header silently stalls every upload, a
/// wrong path orphans every original, and wrong geometry makes the
/// provisional mark visibly jump when the real photo replaces it.
struct CapturePipelineTests {
    @Test func pipelineHeadersMatchSignPhoto() {
        #expect(RemotePhotoSigner.pipelineHeader == "X-Capture-Pipeline")
        #expect(RemotePhotoSigner.capturePipeline == "server-watermark-v1")
        #expect(RemotePhotoSigner.photoIDHeader == "X-Photo-Id")
    }

    /// `sign-photo` writes `${userID}/${photoID}.jpg` into `photo-originals`,
    /// built from the JWT's (lowercase) user id and the lowercased
    /// `X-Photo-Id`.
    @Test func originalPathMatchesWhatSignPhotoWrites() {
        let userID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let photoID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        #expect(VerifiedPhoto.originalsBucket == "photo-originals")
        #expect(
            VerifiedPhoto.originalStoragePath(userID: userID, photoID: photoID)
                == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/11111111-2222-3333-4444-555555555555.jpg"
        )
    }

    /// Mirrors `MARK_SIZE_FRACTION` / `MARK_PADDING_FRACTION` in the Lambda.
    @Test func watermarkGeometryMatchesTheLambda() {
        #expect(PhotoWatermarker.markSizeFraction == 0.09)
        #expect(PhotoWatermarker.markPaddingFraction == 0.035)

        // 1000×800 photo, 0.84-tall artwork: 72px wide, inset 28px.
        let rect = PhotoWatermarker.markRect(in: CGSize(width: 1000, height: 800), markAspectRatio: 0.84)
        #expect(abs(rect.minX - 900) < 0.001)
        #expect(abs(rect.minY - 28) < 0.001)
        #expect(abs(rect.width - 72) < 0.001)
        #expect(abs(rect.height - 72 * 0.84) < 0.001)
    }

    /// The artwork ships in the app bundle. It must be the same PNG as the
    /// Lambda's `assets/brand-mark.png` — asset catalogs recompress, so that
    /// can't be byte-compared here; the dimensions stand in for it. When the
    /// artwork changes, replace it in both repos and update this.
    @Test func watermarkArtworkIsBundled() throws {
        let mark = try #require(UIImage(named: PhotoWatermarker.markAssetName))
        #expect(mark.size.width * mark.scale == 1024)
        #expect(mark.size.height * mark.scale == 860)
    }

    /// A build must keep working against rows (and a schema) without the
    /// column: decoding tolerates its absence, and a `nil` isn't sent at all
    /// — PostgREST rejects an unknown column outright, which would fail the
    /// whole upsert.
    @Test func originalStoragePathIsOptionalOnTheWire() throws {
        var photo = VerifiedPhoto(id: UUID(), userID: UUID(), capturedAt: .now, shortCode: "aB3xK9mP")
        let withoutOriginal = try JSONSerialization.jsonObject(with: JSONEncoder().encode(photo)) as! [String: Any]
        #expect(withoutOriginal["original_storage_path"] == nil)

        photo.originalStoragePath = VerifiedPhoto.originalStoragePath(userID: photo.userID, photoID: photo.id)
        let withOriginal = try JSONSerialization.jsonObject(with: JSONEncoder().encode(photo)) as! [String: Any]
        #expect(withOriginal["original_storage_path"] as? String == photo.originalStoragePath)

        let legacyRow = """
        {"id":"\(photo.id.uuidString)","user_id":"\(photo.userID.uuidString)","storage_path":"a/b.jpg",
         "captured_at":0,"verification_deep_link":"thehumaninternet://photo/x","short_code":"aB3xK9mP"}
        """
        let decoded = try JSONDecoder().decode(VerifiedPhoto.self, from: Data(legacyRow.utf8))
        #expect(decoded.originalStoragePath == nil)
    }
}
