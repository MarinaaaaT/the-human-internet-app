//
//  RemotePhotoSignerTests.swift
//  the-human-internetTests
//

import Testing
import UIKit

@testable import the_human_internet

/// Exercises the AWS server-side signing path (RemotePhotoSigner ->
/// sign-photo Edge Function -> Lambda -> KMS) without a camera, so it runs
/// on the Simulator. It hits the network and needs a real authenticated Supabase session — it rides on whatever
/// session is already persisted in this simulator/bundle id's Keychain from
/// a real Sign in with Apple, rather than faking one. If nothing is signed
/// in, both tests fail fast with a clear message instead of a bare 401.
struct RemotePhotoSignerTests {
    private func makeJPEG() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let image = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    private func requireSession() async throws {
        do {
            _ = try await supabase.auth.session
        } catch {
            Issue.record("No authenticated Supabase session in this simulator — sign in through the app first: \(error)")
            throw error
        }
    }

    @Test func remoteSigningEmbedsAValidManifest() async throws {
        try await requireSession()
        let jpegData = try makeJPEG()

        let signed = try await RemotePhotoSigner.sign(imageData: jpegData)
        #expect(signed.count > jpegData.count)

        // Read the claim back with C2PA's own reader — proves the Lambda's KMS-backed signature and manifest are
        // structurally and cryptographically valid, not just that the
        // network round-trip returned bytes.
        let summary = try #require(try C2PAManifestReader.readManifestJSON(from: signed))
        #expect(summary.contains("c2pa.created"))
        #expect(summary.contains("\"validation_state\": \"Valid\""))

        // Confirms this was signed by the KMS-backed server cert (see
        // aws-signing-lambda/README.md in the backend repo).
        let detailed = try #require(try C2PAManifestReader.readManifestJSON(from: signed, detailed: true))
        #expect(detailed.contains("The Human Internet Server Dev Signer"))

        // digitalSourceType only appears in the detailed view; the summary
        // omits it. This is the assertion that claims a real camera took the
        // photo, so it's the one most worth pinning down — and it's parsed
        // out of the stored assertion rather than string-matched, since a
        // bare `contains` would pass on a match anywhere in the JSON. The v2
        // parser silently drops a snake_case `digital_source_type`, so this
        // is what catches the Lambda's manifest drifting to that spelling.
        let action = try #require(firstStoredAction(in: detailed))
        #expect(action["action"] as? String == "c2pa.created")
        #expect((action["digitalSourceType"] as? String)?.hasSuffix("/digitalCapture") == true)
    }

    @Test func tamperedRemoteSignatureFailsVerification() async throws {
        try await requireSession()
        let jpegData = try makeJPEG()
        var signed = try await RemotePhotoSigner.sign(imageData: jpegData)

        // Flip one byte well past the JPEG/JUMBF header so the file still
        // parses as a JPEG with an intact-looking manifest structure — this
        // has to be a genuine hash-binding failure, not just a corrupt file
        // the reader bails out of early.
        let flipIndex = signed.count - 200
        signed[flipIndex] ^= 0xFF

        let summary = try C2PAManifestReader.readManifestJSON(from: signed)
        #expect(summary == nil || !summary!.contains("\"validation_state\": \"Valid\""))
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
