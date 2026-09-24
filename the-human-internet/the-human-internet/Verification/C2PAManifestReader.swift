//
//  C2PAManifestReader.swift
//  the-human-internet
//

import C2PA
import Foundation

/// Reads a C2PA manifest back out of a signed JPEG. Signing itself happens
/// only server-side now (`RemotePhotoSigner`); this is what lets
/// `RemotePhotoSignerTests` check what the server actually embedded.
///
/// Lives in the app target, not the tests, because a test target that
/// re-links a package product its host app already links fails to build —
/// the tests reach C2PA through here via `@testable import`.
enum C2PAManifestReader {
    /// Returns `nil` when the image carries no manifest at all. Throws only
    /// when a manifest is present but unreadable.
    ///
    /// - Parameter detailed: `Reader.json()` is a summary view that omits
    ///   assertion fields such as `digitalSourceType`; pass `true` for the
    ///   complete manifest, including the raw assertion store.
    static func readManifestJSON(from imageData: Data, detailed: Bool = false) throws -> String? {
        let stream = try Stream(data: imageData)
        guard let reader = try? Reader(format: "image/jpeg", stream: stream) else {
            return nil
        }
        return detailed ? try reader.detailedJSON() : try reader.json()
    }
}
