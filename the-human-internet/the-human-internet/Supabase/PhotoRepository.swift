//
//  PhotoRepository.swift
//  the-human-internet
//

import Foundation
import Supabase

enum PhotoRepository {
    /// Object paths are namespaced "{user_id}/{photo_id}.jpg" — Storage RLS
    /// checks ownership from the path itself.
    static func upload(imageData: Data, userID: UUID) async throws -> VerifiedPhoto {
        let photoID = UUID()
        // Lowercased to match Postgres's canonical uuid text rendering — Swift's
        // UUID.uuidString is uppercase, which the Storage RLS policy casts to
        // uuid to compare by value regardless, but keeping this consistent too.
        let path = "\(userID.uuidString.lowercased())/\(photoID.uuidString.lowercased()).jpg"

        try await supabase.storage
            .from("photos")
            .upload(path, data: imageData, options: FileOptions(contentType: "image/jpeg"))

        let photo = VerifiedPhoto(
            id: photoID,
            userID: userID,
            storagePath: path,
            capturedAt: .now,
            // Lowercased for the same reason as the storage path above —
            // consistency with Postgres's canonical uuid text rendering.
            verificationDeepLink: "thehumaninternet://photo/\(photoID.uuidString.lowercased())"
        )
        try await supabase
            .from("photos")
            .insert(photo)
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
