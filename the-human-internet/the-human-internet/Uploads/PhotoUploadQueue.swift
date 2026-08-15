//
//  PhotoUploadQueue.swift
//  the-human-internet
//

import Foundation

/// Persists a raw captured photo to disk *before* returning, so it can
/// survive a force-quit, then drives watermarking + signing (if not already
/// done) and the actual Supabase upload in the background — the capture
/// flow never blocks on any of that.
///
/// The on-disk manifest is the durable source of truth for "what's still
/// pending"; `AppState.photos`/`processingPhotoIDs`/`failedPhotoIDs` are just
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
        var isSigned: Bool

        init(id: UUID, userID: UUID, capturedAt: Date, shortCode: String, isSigned: Bool) {
            self.id = id
            self.userID = userID
            self.capturedAt = capturedAt
            self.shortCode = shortCode
            self.isSigned = isSigned
        }

        // Entries written before signing moved into `drive()` have no
        // `isSigned` key — `enqueue` only ever wrote already-signed data
        // back then, so absence means "signed", not the synthesized default.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            userID = try container.decode(UUID.self, forKey: .userID)
            capturedAt = try container.decode(Date.self, forKey: .capturedAt)
            shortCode = try container.decode(String.self, forKey: .shortCode)
            isSigned = try container.decodeIfPresent(Bool.self, forKey: .isSigned) ?? true
        }
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

    /// How many photos may run the memory-heavy watermark + sign stage at
    /// once. Each holds a full-resolution bitmap (~100MB for a 12MP capture),
    /// and the shutter deliberately no longer serializes captures, so an
    /// unbounded burst of rapid taps would otherwise be enough to get the app
    /// jetsammed. Nothing user-facing waits on this stage, so queueing behind
    /// a slot costs nothing perceptible.
    private static let maxConcurrentProcessing = 2
    private static var activeProcessingCount = 0
    private static var processingWaiters: [CheckedContinuation<Void, Never>] = []

    private static func acquireProcessingSlot() async {
        if activeProcessingCount < maxConcurrentProcessing {
            activeProcessingCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            processingWaiters.append(continuation)
        }
        // The slot was handed over directly by `releaseProcessingSlot`, which
        // left `activeProcessingCount` untouched — incrementing here would
        // double-count it.
    }

    private static func releaseProcessingSlot() {
        // Hands the slot straight to the next waiter rather than decrementing
        // and re-incrementing: `resume()` only schedules that task, so a gap
        // in the count would let an unrelated `acquire` slip in over the cap.
        if processingWaiters.isEmpty {
            activeProcessingCount -= 1
        } else {
            processingWaiters.removeFirst().resume()
        }
    }

    /// Writes the raw (not yet watermarked or signed) captured image to disk
    /// and appends it to the manifest before returning, then kicks off
    /// watermarking, signing, and the network upload in the background.
    /// Returns an optimistic `VerifiedPhoto` the caller can show immediately.
    static func enqueue(imageData: Data, userID: UUID, appState: AppState) throws -> VerifiedPhoto {
        let photoID = UUID()
        let capturedAt = Date.now
        let shortCode = VerifiedPhoto.generateShortCode()

        try imageData.write(to: fileURL(for: photoID), options: .atomic)
        var manifest = loadManifest()
        manifest.append(PendingUpload(id: photoID, userID: userID, capturedAt: capturedAt, shortCode: shortCode, isSigned: false))
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
        appState.processingPhotoIDs.remove(photoID)
        appState.failedPhotoIDs.remove(photoID)
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
        // Guards against a resume and a manual retry racing to sign/upload
        // the same photo at once — this only clears once signing *and*
        // upload both finish (or either fails), so it covers both stages.
        guard !appState.processingPhotoIDs.contains(photoID) else { return }
        appState.processingPhotoIDs.insert(photoID)
        appState.failedPhotoIDs.remove(photoID)

        Task {
            do {
                var imageData = try Data(contentsOf: fileURL(for: photoID))

                // Missing manifest entry (e.g. raced with
                // cancelPendingUpload) shouldn't retrigger watermarking/signing.
                let isSigned = loadManifest().first(where: { $0.id == photoID })?.isSigned ?? true
                if !isSigned {
                    await acquireProcessingSlot()
                    defer { releaseProcessingSlot() }

                    // Burned into the pixels *before* signing, so the C2PA
                    // manifest's hash binding covers the exact bytes that
                    // get uploaded and shared — signing the raw capture and
                    // watermarking afterward would invalidate that binding.
                    let watermarkedData = try await PhotoWatermarker.watermark(imageData: imageData)

                    let signedData: Data
                    if appState.isAWSServerSideSigningEnabled {
                        signedData = try await RemotePhotoSigner.sign(imageData: watermarkedData)
                    } else {
                        // C2PA signing is a synchronous, potentially non-trivial
                        // native call — detached so it doesn't block this task's
                        // (main) actor.
                        signedData = try await Task.detached(priority: .userInitiated) {
                            try PhotoSigner.sign(imageData: watermarkedData)
                        }.value
                    }
                    try signedData.write(to: fileURL(for: photoID), options: .atomic)
                    markSigned(photoID: photoID)
                    imageData = signedData
                }

                let photo = try await PhotoRepository.upload(
                    imageData: imageData, photoID: photoID, userID: userID, capturedAt: capturedAt, shortCode: shortCode
                )
                removeFromManifest(photoID: photoID)
                try? FileManager.default.removeItem(at: fileURL(for: photoID))
                appState.processingPhotoIDs.remove(photoID)
                if let index = appState.photos.firstIndex(where: { $0.id == photoID }) {
                    appState.photos[index] = photo
                }
            } catch {
                appState.processingPhotoIDs.remove(photoID)
                appState.failedPhotoIDs.insert(photoID)
                debugPrint(error)
            }
        }
    }

    private static func markSigned(photoID: UUID) {
        var manifest = loadManifest()
        guard let index = manifest.firstIndex(where: { $0.id == photoID }) else { return }
        manifest[index].isSigned = true
        saveManifest(manifest)
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
