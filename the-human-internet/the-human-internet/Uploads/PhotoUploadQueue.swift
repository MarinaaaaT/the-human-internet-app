//
//  PhotoUploadQueue.swift
//  the-human-internet
//

import Foundation

/// Persists a captured, signed photo to disk *before* returning, so it can
/// survive a force-quit, then drives the actual Supabase upload in the
/// background — the capture flow never blocks on the network.
///
/// The on-disk manifest is the durable source of truth for "what's still
/// pending"; `AppState.photos`/`uploadingPhotoIDs`/`failedUploadIDs` are just
/// an in-memory reflection of it for the UI. `AppState.hydrate` calls
/// `resumePendingUploads` on every launch (cold start and fresh sign-in
/// alike) so anything interrupted picks back up automatically.
@MainActor
enum PhotoUploadQueue {
    private struct PendingUpload: Codable {
        let id: UUID
        let userID: UUID
        let capturedAt: Date
        let shortCode: String
    }

    private static let directory: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingUploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private static let manifestURL = directory.appendingPathComponent("manifest.json")

    /// A foreign entry (belonging to a user who isn't the one currently
    /// hydrating) this old is assumed abandoned by a session that ended
    /// before `pruneOnSignOut` ran — e.g. a crash, or an upgrade from before
    /// this existed — and gets swept rather than lingering on disk forever.
    private static let staleForeignEntryMaxAge: TimeInterval = 7 * 24 * 60 * 60

    /// Even a signed-in user's own permanently-failing upload (bad network,
    /// revoked auth, a server-side rejection that never clears) must not sit
    /// on disk indefinitely.
    private static let maxPendingAge: TimeInterval = 30 * 24 * 60 * 60
    private static let maxPendingCount = 200

    /// Writes the signed image to disk and appends it to the manifest before
    /// returning, then kicks off the network upload in the background.
    /// Returns an optimistic `VerifiedPhoto` the caller can show immediately.
    static func enqueue(imageData: Data, userID: UUID, appState: AppState) throws -> VerifiedPhoto {
        let photoID = UUID()
        let capturedAt = Date.now
        let shortCode = VerifiedPhoto.generateShortCode()

        try imageData.write(to: fileURL(for: photoID), options: .atomic)
        var manifest = loadManifest()
        manifest.append(PendingUpload(id: photoID, userID: userID, capturedAt: capturedAt, shortCode: shortCode))
        saveManifest(manifest)

        drive(photoID: photoID, userID: userID, capturedAt: capturedAt, shortCode: shortCode, appState: appState)

        return VerifiedPhoto(
            id: photoID,
            userID: userID,
            storagePath: storagePath(userID: userID, photoID: photoID),
            capturedAt: capturedAt,
            verificationDeepLink: "thehumaninternet://photo/\(photoID.uuidString.lowercased())",
            shortCode: shortCode
        )
    }

    /// Resumes any uploads left pending by a prior force-quit or crash.
    /// `hydrate`'s `PhotoRepository.fetchAll` only returns photos that
    /// already made it into the DB, so anything still pending is seeded into
    /// `appState.photos` here as well — otherwise it wouldn't appear until
    /// its upload finishes.
    static func resumePendingUploads(userID: UUID, appState: AppState) {
        sweep(currentUserID: userID)
        for item in loadManifest() where item.userID == userID {
            if !appState.photos.contains(where: { $0.id == item.id }) {
                let photo = VerifiedPhoto(
                    id: item.id,
                    userID: item.userID,
                    storagePath: storagePath(userID: item.userID, photoID: item.id),
                    capturedAt: item.capturedAt,
                    verificationDeepLink: "thehumaninternet://photo/\(item.id.uuidString.lowercased())",
                    shortCode: item.shortCode
                )
                appState.photos.append(photo)
            }
            drive(photoID: item.id, userID: item.userID, capturedAt: item.capturedAt, shortCode: item.shortCode, appState: appState)
        }
        appState.photos.sort { $0.capturedAt > $1.capturedAt }
    }

    /// Manually re-attempts a specific upload that previously failed.
    static func retry(photoID: UUID, appState: AppState) {
        guard let item = loadManifest().first(where: { $0.id == photoID }) else { return }
        drive(photoID: item.id, userID: item.userID, capturedAt: item.capturedAt, shortCode: item.shortCode, appState: appState)
    }

    /// The on-disk copy of a photo that's still pending upload, or `nil` once
    /// the upload has completed and the local copy was cleaned up.
    /// `RemotePhotoImage` checks this first so a just-captured photo's
    /// thumbnail shows instantly from disk, instead of fetching from Storage
    /// before the background upload has actually put anything there.
    static func localImageData(for photoID: UUID) -> Data? {
        try? Data(contentsOf: fileURL(for: photoID))
    }

    /// Clears any local trace of a photo — its manifest entry, pending file,
    /// and uploading/failed status — regardless of what stage its upload was
    /// at. Used when deleting a photo so a still-uploading or previously
    /// failed one can't resurface later via a resumed upload.
    ///
    /// Doesn't cancel an upload already in flight: that's a narrow, rare
    /// race (delete landing in the same instant as a background upload
    /// completing), and `PhotoRepository.delete`'s DB-row delete is what
    /// actually matters for the verification link either way.
    static func cancelPendingUpload(photoID: UUID, appState: AppState) {
        removeFromManifest(photoID: photoID)
        try? FileManager.default.removeItem(at: fileURL(for: photoID))
        appState.uploadingPhotoIDs.remove(photoID)
        appState.failedUploadIDs.remove(photoID)
    }

    /// Deletes every pending file and manifest entry owned by `userID`.
    /// Called from `AppState.signOut()` so a signed-out session leaves no
    /// un-uploaded photo behind for the next person to recover on a shared
    /// device. Doesn't cancel an upload already in flight — same narrow,
    /// rare race noted on `cancelPendingUpload`; its completion handler's
    /// own manifest/file cleanup is a harmless no-op if this already ran.
    static func pruneOnSignOut(userID: UUID) {
        var manifest = loadManifest()
        for item in manifest where item.userID == userID {
            try? FileManager.default.removeItem(at: fileURL(for: item.id))
        }
        manifest.removeAll { $0.userID == userID }
        saveManifest(manifest)
    }

    /// Enforces the staleness/count limits above and drops foreign entries a
    /// prior sign-out never got to clean up (crash, force-quit, or upgrading
    /// from before `pruneOnSignOut` existed).
    private static func sweep(currentUserID: UUID) {
        let manifest = loadManifest()
        let now = Date.now

        var kept: [PendingUpload] = []
        var removed: [PendingUpload] = []
        for item in manifest {
            let age = now.timeIntervalSince(item.capturedAt)
            let isStale = item.userID == currentUserID ? age > maxPendingAge : age > staleForeignEntryMaxAge
            if isStale {
                removed.append(item)
            } else {
                kept.append(item)
            }
        }

        if kept.count > maxPendingCount {
            kept.sort { $0.capturedAt > $1.capturedAt }
            removed.append(contentsOf: kept.suffix(from: maxPendingCount))
            kept = Array(kept.prefix(maxPendingCount))
        }

        guard !removed.isEmpty else { return }
        for item in removed {
            try? FileManager.default.removeItem(at: fileURL(for: item.id))
        }
        saveManifest(kept)
    }

    private static func drive(photoID: UUID, userID: UUID, capturedAt: Date, shortCode: String, appState: AppState) {
        // Guards against a resume and a manual retry racing to upload the
        // same photo at once.
        guard !appState.uploadingPhotoIDs.contains(photoID) else { return }
        appState.uploadingPhotoIDs.insert(photoID)
        appState.failedUploadIDs.remove(photoID)

        Task {
            do {
                let imageData = try Data(contentsOf: fileURL(for: photoID))
                let photo = try await PhotoRepository.upload(
                    imageData: imageData, photoID: photoID, userID: userID, capturedAt: capturedAt, shortCode: shortCode
                )
                removeFromManifest(photoID: photoID)
                try? FileManager.default.removeItem(at: fileURL(for: photoID))
                appState.uploadingPhotoIDs.remove(photoID)
                if let index = appState.photos.firstIndex(where: { $0.id == photoID }) {
                    appState.photos[index] = photo
                }
            } catch {
                appState.uploadingPhotoIDs.remove(photoID)
                appState.failedUploadIDs.insert(photoID)
                debugPrint(error)
            }
        }
    }

    private static func storagePath(userID: UUID, photoID: UUID) -> String {
        "\(userID.uuidString.lowercased())/\(photoID.uuidString.lowercased()).jpg"
    }

    private static func fileURL(for photoID: UUID) -> URL {
        directory.appendingPathComponent("\(photoID.uuidString.lowercased()).jpg")
    }

    private static func loadManifest() -> [PendingUpload] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder().decode([PendingUpload].self, from: data)) ?? []
    }

    private static func saveManifest(_ manifest: [PendingUpload]) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private static func removeFromManifest(photoID: UUID) {
        var manifest = loadManifest()
        manifest.removeAll { $0.id == photoID }
        saveManifest(manifest)
    }
}
