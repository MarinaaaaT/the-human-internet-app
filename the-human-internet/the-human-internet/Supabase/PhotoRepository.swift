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
    /// `hasOriginal`: whether `sign-photo`'s capture pipeline stored this
    /// photo's signed capture in `photo-originals`, which the row then points
    /// at. `imageData` is always the watermarked photo — never the original.
    static func upload(
        imageData: Data,
        photoID: UUID,
        userID: UUID,
        capturedAt: Date,
        shortCode: String,
        hasOriginal: Bool
    ) async throws -> VerifiedPhoto {
        var photo = VerifiedPhoto(id: photoID, userID: userID, capturedAt: capturedAt, shortCode: shortCode)
        if hasOriginal {
            photo.originalStoragePath = VerifiedPhoto.originalStoragePath(userID: userID, photoID: photoID)
        }

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

    /// Who took `photoID`, and what they publish alongside it — see
    /// `PhotoOwnerProfile`.
    ///
    /// An RPC rather than a join, because there is no join available: RLS on
    /// `users` is self-only, so selecting the owner's row from an app user's
    /// session returns nothing. `get_photo_owner_profile` is
    /// security-definer and hands back only the fields a verification page
    /// shows, already gated.
    static func fetchOwnerProfile(photoID: UUID) async throws -> PhotoOwnerProfile? {
        let rows: [PhotoOwnerProfile] = try await supabase
            .rpc("get_photo_owner_profile", params: ["p_photo_id": photoID.uuidString.lowercased()])
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
    ///
    /// The signed capture in `photo-originals` goes too. Its path is derived
    /// rather than read from `originalStoragePath`, because a photo deleted
    /// while still uploading can already have one stored by `sign-photo`
    /// with no row pointing at it yet; removing an object that doesn't exist
    /// is a no-op.
    static func delete(photo: VerifiedPhoto) async throws {
        try await supabase
            .from("photos")
            .delete()
            .eq("id", value: photo.id)
            .execute()
        try? await supabase.storage.from("photos").remove(paths: [photo.storagePath])
        try? await supabase.storage.from(VerifiedPhoto.originalsBucket).remove(paths: [originalPath(of: photo)])
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
        try? await supabase.storage.from(VerifiedPhoto.originalsBucket).remove(paths: photos.map(originalPath(of:)))
    }

    private static func originalPath(of photo: VerifiedPhoto) -> String {
        VerifiedPhoto.originalStoragePath(userID: photo.userID, photoID: photo.id)
    }
}
