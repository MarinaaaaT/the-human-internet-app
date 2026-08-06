//
//  PhotoSignerTests.swift
//  the-human-internetTests
//

import Testing
import UIKit

@testable import the_human_internet

/// Exercises PhotoSigner without a camera — pure in-memory signing, so it
/// runs fine on the Simulator (which has no camera hardware at all) and
/// doesn't depend on the live capture pipeline being testable there.
///
/// Deliberately reaches C2PA only through the app target's own API rather
/// than importing the package here: a test target that re-links a package
/// product its host app already links fails to build.
struct PhotoSignerTests {
    private func makeJPEG() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    @Test func signingEmbedsAManifest() throws {
        let jpegData = try makeJPEG()

        // Guards the test itself: if the fixture already had a manifest,
        // the assertions below would prove nothing.
        #expect(try PhotoSigner.readManifestJSON(from: jpegData) == nil)

        let signed = try PhotoSigner.sign(imageData: jpegData)
        #expect(signed.count > jpegData.count)

        // Read the claim back with C2PA's own reader rather than just
        // trusting that `sign` didn't throw — confirms the manifest says
        // what PhotoSigner intends: a fresh capture, not an edit.
        let summary = try #require(try PhotoSigner.readManifestJSON(from: signed))
        #expect(summary.contains("c2pa.created"))
        // The signature itself must verify and the content hash must bind —
        // this is what makes the photo tamper-evident.
        #expect(summary.contains("\"validation_state\": \"Valid\""))

        // digitalSourceType only appears in the detailed view; the summary
        // omits it. This is the assertion that claims a real camera took the
        // photo, so it's the one most worth pinning down — and it's parsed
        // out of the stored assertion rather than string-matched, since a
        // bare `contains` would pass on a match anywhere in the JSON.
        let detailed = try #require(try PhotoSigner.readManifestJSON(from: signed, detailed: true))
        let action = try #require(firstStoredAction(in: detailed))
        #expect(action["action"] as? String == "c2pa.created")
        #expect(
            (action["digitalSourceType"] as? String)?.hasSuffix("/digitalCapture") == true,
            "the capture claim must survive signing — see PhotoSigner.manifestJSON"
        )
    }

    /// Digs the first `c2pa.actions.v2` action out of the detailed manifest's
    /// assertion store, which is the authoritative record of what was signed.
    private func firstStoredAction(in detailedJSON: String) -> [String: Any]? {
        guard
            let data = detailedJSON.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let manifests = root["manifests"] as? [String: Any],
            let manifest = manifests.values.first as? [String: Any],
            let store = manifest["assertion_store"] as? [String: Any],
            let actions = store["c2pa.actions.v2"] as? [String: Any],
            let list = actions["actions"] as? [[String: Any]]
        else { return nil }
        return list.first
    }
}
