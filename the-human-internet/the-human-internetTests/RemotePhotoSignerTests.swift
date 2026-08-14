//
//  RemotePhotoSignerTests.swift
//  the-human-internetTests
//

import Testing
import UIKit

@testable import the_human_internet

/// Exercises the AWS server-side signing path (RemotePhotoSigner ->
/// sign-photo Edge Function -> Lambda -> KMS) without a camera, the same
/// reasoning as PhotoSignerTests. Unlike PhotoSigner, this hits the network
/// and needs a real authenticated Supabase session — it rides on whatever
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

        // Read the claim back through the same C2PA reader PhotoSignerTests
        // uses — proves the Lambda's KMS-backed signature and manifest are
        // structurally and cryptographically valid, not just that the
        // network round-trip returned bytes.
        let summary = try #require(try PhotoSigner.readManifestJSON(from: signed))
        #expect(summary.contains("c2pa.created"))
        #expect(summary.contains("\"validation_state\": \"Valid\""))

        // Confirms this actually went through the KMS-backed server path
        // and not, say, an accidental fallback to the bundled dev cert —
        // the two dev CAs have deliberately distinct common names (see
        // aws-signing-lambda/README.md and Verification/README.md).
        let detailed = try #require(try PhotoSigner.readManifestJSON(from: signed, detailed: true))
        #expect(detailed.contains("The Human Internet Server Dev Signer"))
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

        let summary = try PhotoSigner.readManifestJSON(from: signed)
        #expect(summary == nil || !summary!.contains("\"validation_state\": \"Valid\""))
    }
}
