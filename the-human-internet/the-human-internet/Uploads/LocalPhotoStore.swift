//
//  LocalPhotoStore.swift
//  the-human-internet
//

import Foundation

/// On-device copies of the signed-in user's own photos, so the Profile grid
/// and photo detail open them from disk instead of downloading them from
/// Storage every time — which, on a weak signal, was most of what made
/// browsing your own photos feel slow.
///
/// Every copy is the exact bytes in the `photos` bucket — the finished
/// photo, its mark already in the pixels — never the raw capture. A photo
/// taken on this device is moved in from `PendingUploads/` the moment its
/// upload lands (`adopt`); any other (taken on another device, or before
/// this existed) is written here the first time it's downloaded (`store`).
/// So nothing is drawn over these and nothing swaps in later. Until a
/// photo's mark exists at all, its pending copy plus `ProvisionalWatermark`
/// covers it, as before.
///
/// Only views that opt in read from here (`RemotePhotoImage.usesLocalCopy`).
/// The verification page doesn't: it shows what everyone else is shown, so
/// it always loads from Storage.
///
/// A cache, not a source of truth. It lives in Caches, which iOS may empty
/// when the device runs low on space, and anything missing just downloads
/// again — unlike `PendingUploads/`, losing it loses nothing.
enum LocalPhotoStore {
    /// Past this, the least recently opened photos are deleted first. About
    /// 150 full-resolution captures.
    static let byteBudget = 500 * 1024 * 1024

    private static let root: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LocalPhotos", isDirectory: true)

    /// Writes, removals and trims run here one at a time and in order, off
    /// the main thread. Reads don't need it: every write is atomic, so a
    /// reader sees a whole file or none.
    private static let queue = DispatchQueue(label: "LocalPhotoStore", qos: .utility)

    /// The photo's bytes, or `nil` if this device doesn't have them. Reads
    /// synchronously, so call it off the main thread where it matters.
    /// Counts as opening the photo, for eviction.
    static func data(photoID: UUID, userID: UUID) -> Data? {
        let url = fileURL(photoID: photoID, userID: userID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        markUsed(url)
        return data
    }

    /// Keeps a copy of a photo just downloaded from Storage.
    static func store(_ data: Data, photoID: UUID, userID: UUID) {
        let url = fileURL(photoID: photoID, userID: userID)
        queue.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            trim()
        }
    }

    /// Moves a just-uploaded photo's pending file in. A rename rather than a
    /// copy, and synchronous, so there's no moment where the photo is in
    /// neither place and a tile appearing just then has to download it.
    static func adopt(fileAt source: URL, photoID: UUID, userID: UUID) {
        let destination = fileURL(photoID: photoID, userID: userID)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: source, to: destination)
            // Moving keeps the file's own date, which for an upload that
            // failed for days would make a photo just taken the first to go.
            markUsed(destination)
        } catch {
            // Only the cache misses out — the photo downloads instead. The
            // pending file must still go, as it always has once uploaded.
            try? fileManager.removeItem(at: source)
        }
        queue.async { trim() }
    }

    /// Called when a photo is deleted, so it can't be shown again from here.
    static func remove(photoID: UUID) {
        queue.async {
            for directory in userDirectories() {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName(for: photoID)))
            }
        }
    }

    /// Deletes every user's copies but `userID`'s — or everyone's, when
    /// `nil`. Sign-out passes `nil`, so the next person on a shared device
    /// can't surface the previous user's photos; `hydrate` passes the user
    /// signing in, which clears what a session that ended without signing
    /// out (revoked, or expired) left behind.
    static func removeAll(except userID: UUID? = nil) {
        let kept = userID.map(directoryName(for:))
        queue.async {
            for directory in userDirectories() where directory.lastPathComponent != kept {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    struct StoredFile: Equatable {
        let url: URL
        let size: Int
        let lastUsed: Date
    }

    /// The least recently used files to delete to bring `files` within
    /// `budget` bytes, oldest first.
    static func filesToEvict(from files: [StoredFile], budget: Int) -> [StoredFile] {
        var total = files.reduce(0) { $0 + $1.size }
        var evicted: [StoredFile] = []
        for file in files.sorted(by: { $0.lastUsed < $1.lastUsed }) where total > budget {
            evicted.append(file)
            total -= file.size
        }
        return evicted
    }

    /// `{user_id}/{photo_id}.jpg`, both lowercased — the same shape as the
    /// photo's storage path, but built from the ids rather than read from the
    /// row, so a stored path can never point a write outside this folder.
    static func fileURL(photoID: UUID, userID: UUID) -> URL {
        root
            .appendingPathComponent(directoryName(for: userID), isDirectory: true)
            .appendingPathComponent(fileName(for: photoID))
    }

    private static func directoryName(for userID: UUID) -> String {
        userID.uuidString.lowercased()
    }

    private static func fileName(for photoID: UUID) -> String {
        "\(photoID.uuidString.lowercased()).jpg"
    }

    private static func userDirectories() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    }

    /// Eviction goes by modification date, so opening a photo bumps it.
    private static func markUsed(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: url.path)
    }

    private static func trim() {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return }
        var files: [StoredFile] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            files.append(StoredFile(url: url, size: values.fileSize ?? 0, lastUsed: values.contentModificationDate ?? .distantPast))
        }
        for file in filesToEvict(from: files, budget: byteBudget) {
            try? FileManager.default.removeItem(at: file.url)
        }
    }
}
