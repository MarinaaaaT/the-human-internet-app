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
        let photo = VerifiedPhoto(id: photoID, userID: userID, capturedAt: capturedAt, shortCode: shortCode)

        // Uploaded to the path the photo itself carries, so the object and the
        // row can't disagree about where the bytes live.
        try await supabase.storage
            .from("photos")
            .upload(photo.storagePath, data: imageData, options: FileOptions(contentType: "image/jpeg", upsert: true))

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

    /// Deletes the DB row first — that's what `fetch(photoID:)` (the
    /// verification page's lookup) depends on, so it's what actually kills
    /// the link. The Storage object cleanup after it is best-effort: a
    /// failure there just leaves an orphaned, otherwise-unreachable file
    /// behind rather than a dead link with a lingering row.
    static func delete(photo: VerifiedPhoto) async throws {
        try await supabase
            .from("photos")
            .delete()
            .eq("id", value: photo.id)
            .execute()
        try? await supabase.storage.from("photos").remove(paths: [photo.storagePath])
    }

    /// Batched sibling of `delete(photo:)` — same DB-row-first, storage-is-best-effort
    /// ordering, for the Profile grid's multi-select delete.
    static func delete(photos: [VerifiedPhoto]) async throws {
        guard !photos.isEmpty else { return }
        try await supabase
            .from("photos")
            .delete()
            .in("id", values: photos.map(\.id))
            .execute()
        try? await supabase.storage.from("photos").remove(paths: photos.map(\.storagePath))
    }
}
