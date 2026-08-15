//
//  PhotoLibrarySaver.swift
//  the-human-internet
//

import Foundation
import Photos

enum PhotoLibrarySaverError: Error {
    case accessDenied
}

/// Saves a captured photo to the user's own device Photos library so they
/// don't lose their pictures — nothing more. This copy is deliberately the
/// raw capture: no watermark and **no C2PA manifest**, since the watermark
/// has to be burned in before signing and nobody but the user ever sees
/// this copy. It carries no provenance claim and can't be verified — only
/// the hosted copy can. `PhotoUploadQueue` is what durably persists the
/// signed bytes and resumes them across launches; don't treat anything in
/// the library as a verifiable fallback for that.
enum PhotoLibrarySaver {
    /// Writes the capture's own bytes via `PHAssetCreationRequest` rather
    /// than round-tripping through `UIImage`, which would recompress the
    /// photo and drop its EXIF.
    static func save(imageData: Data) async throws {
        guard await isAuthorized() else { throw PhotoLibrarySaverError.accessDenied }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: imageData, options: nil)
        }
    }

    /// Add-only authorization — the app only ever adds photos, never reads
    /// the library, so this asks for the narrower of the two permissions.
    private static func isAuthorized() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited
        default:
            return false
        }
    }
}
