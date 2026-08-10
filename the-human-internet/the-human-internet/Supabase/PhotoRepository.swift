//
//  PhotoRepository.swift
//  the-human-internet
//

import Foundation
import Supabase

enum PhotoRepository {
    /// Object paths are namespaced "{user_id}/{photo_id}.jpg" — Storage RLS
    /// checks ownership from the path itself.
    ///
    /// `photoID`/`capturedAt` are supplied by the caller (rather than
    /// generated here) so `PhotoUploadQueue` can retry an interrupted upload
    /// — after a force-quit, or a manual retry — with the exact same
    /// identity every time. Both the storage upload and the DB write use
    /// upsert, so calling this twice for the same `photoID` (e.g. the
    /// process died between the two) is harmless.
    static func upload(imageData: Data, photoID: UUID, userID: UUID, capturedAt: Date, shortCode: String) async throws -> VerifiedPhoto {
        // Lowercased to match Postgres's canonical uuid text rendering — Swift's
        // UUID.uuidString is uppercase, which the Storage RLS policy casts to
        // uuid to compare by value regardless, but keeping this consistent too.
        let path = "\(userID.uuidString.lowercased())/\(photoID.uuidString.lowercased()).jpg"

        try await supabase.storage
            .from("photos")
            .upload(path, data: imageData, options: FileOptions(contentType: "image/jpeg", upsert: true))

        let photo = VerifiedPhoto(
            id: photoID,
            userID: userID,
            storagePath: path,
            capturedAt: capturedAt,
            // Lowercased for the same reason as the storage path above —
            // consistency with Postgres's canonical uuid text rendering.
            verificationDeepLink: "thehumaninternet://photo/\(photoID.uuidString.lowercased())",
            shortCode: shortCode
        )
        try await supabase
            .from("photos")
            .upsert(photo, onConflict: "id")
            .execute()
        return photo
    }

    static func fetch(photoID: UUID) async throws -> VerifiedPhoto? {
        let rows: [VerifiedPhoto] = try await supabase
            .from("photos")
            .select()
            .eq("id", value: photoID)
            .execute()
            .value
        return rows.first
    }

    static func fetchAll(userID: UUID) async throws -> [VerifiedPhoto] {
        try await supabase
            .from("photos")
            .select()
            .eq("user_id", value: userID)
            .order("captured_at", ascending: false)
            .execute()
            .value
    }

    static func downloadImage(path: String) async throws -> Data {
        try await supabase.storage.from("photos").download(path: path)
    }
}
