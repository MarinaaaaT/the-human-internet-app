//
//  PhotoSigner.swift
//  the-human-internet
//

import C2PA
import Foundation

enum PhotoSignerError: Error {
    case missingDevCredentials
}

/// Embeds a C2PA content-credential manifest into a freshly captured photo,
/// asserting it came from a physical camera (`digitalCapture`).
///
/// Signed with a locally-generated, self-signed dev certificate — see
/// Verification/README.md. Real, verifiable manifests (genuine hash binding,
/// genuine tamper evidence), just not yet chained to a publicly-trusted
/// authority. Swapping in a real certificate later, once the C2PA Conformance
/// Program is complete, only touches `loadSigner()` below.
enum PhotoSigner {
    /// IPTC term asserting the image came off a physical capture device.
    private static let digitalCaptureURI =
        "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"

    /// Hand-written rather than built from `ManifestDefinition`/`Action`.
    ///
    /// Swift's `Action` encodes the key as `digital_source_type`, but the
    /// C2PA **v2** actions assertion spells it `digitalSourceType`; the v2
    /// parser doesn't recognise the snake_case form and silently drops it,
    /// degrading the claim to a bare `c2pa.created`. Verified by reading the
    /// raw assertion store back out — see PhotoSignerTests. Writing the JSON
    /// directly is the only way to control the key, and this assertion is
    /// the whole point of signing: it's what says a real camera took the photo.
    private static let manifestJSON = """
    {
      "claim_version": 2,
      "format": "image/jpeg",
      "title": "the-human-internet-capture.jpg",
      "claim_generator_info": [
        { "name": "the-human-internet" }
      ],
      "assertions": [
        {
          "label": "c2pa.actions.v2",
          "data": {
            "actions": [
              {
                "action": "c2pa.created",
                "digitalSourceType": "\(digitalCaptureURI)"
              }
            ]
          }
        }
      ]
    }
    """

    /// Signs `imageData` (a JPEG) and returns the signed JPEG bytes.
    static func sign(imageData: Data) throws -> Data {
        let signer = try loadSigner()

        let builder = try Builder(manifestJSON: Self.manifestJSON)

        let sourceStream = try Stream(data: imageData)
        // c2pa-swift's writable stream is file-backed (no in-memory write
        // stream convenience), so the signed output round-trips through a
        // scratch file that's cleaned up immediately after reading it back.
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        defer { try? FileManager.default.removeItem(at: destinationURL) }
        let destinationStream = try Stream(writeTo: destinationURL)

        try builder.sign(
            format: "image/jpeg",
            source: sourceStream,
            destination: destinationStream,
            signer: signer
        )

        return try Data(contentsOf: destinationURL)
    }

    /// Reads the C2PA manifest back out of a signed JPEG, as JSON.
    ///
    /// Returns `nil` when the image carries no manifest at all. Throws only
    /// when a manifest is present but unreadable.
    ///
    /// - Parameter detailed: `Reader.json()` is a summary view that omits
    ///   assertion fields such as `digital_source_type`; pass `true` for the
    ///   complete manifest.
    static func readManifestJSON(from imageData: Data, detailed: Bool = false) throws -> String? {
        let stream = try Stream(data: imageData)
        guard let reader = try? Reader(format: "image/jpeg", stream: stream) else {
            return nil
        }
        return detailed ? try reader.detailedJSON() : try reader.json()
    }

    private static func loadSigner() throws -> Signer {
        guard
            let certURL = Bundle.main.url(forResource: "C2PADevCertificate", withExtension: "pem"),
            let keyURL = Bundle.main.url(forResource: "C2PADevPrivateKey", withExtension: "pem"),
            let certPEM = try? String(contentsOf: certURL, encoding: .utf8),
            let keyPEM = try? String(contentsOf: keyURL, encoding: .utf8)
        else {
            throw PhotoSignerError.missingDevCredentials
        }

        let info = SignerInfo(
            algorithm: .es256,
            certificatePEM: certPEM,
            privateKeyPEM: keyPEM,
            tsa: nil
        )
        return try Signer(info: info)
    }
}
