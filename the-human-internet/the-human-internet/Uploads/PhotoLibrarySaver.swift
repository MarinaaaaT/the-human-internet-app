//
//  PhotoLibrarySaver.swift
//  the-human-internet
//

import Foundation
import Photos

enum PhotoLibrarySaverError: Error {
    case accessDenied
}

/// Saves a captured photo to the user's own device Photos library — the
/// fallback copy if the Supabase upload never finishes (app force-quit,
/// deleted, etc. before the queue can complete it).
enum PhotoLibrarySaver {
    /// Writes the exact signed JPEG bytes via `PHAssetCreationRequest`
    /// rather than round-tripping through `UIImage`, which would re-encode
    /// the file and strip the embedded C2PA manifest.
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
