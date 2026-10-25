//
//  LocalPhotoStoreTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// The Profile grid and photo detail show the user's own photos from disk.
/// A photo taken here moves into the store once uploaded, is read back
/// under its owner only, and the least recently opened go first once the
/// store is over budget.
struct LocalPhotoStoreTests {
    @Test func anUploadedPhotoMovesInAndReadsBack() throws {
        let photoID = UUID()
        let userID = UUID()
        let bytes = Data("finished photo".utf8)
        let pending = FileManager.default.temporaryDirectory.appendingPathComponent("\(photoID).jpg")
        try bytes.write(to: pending)
        defer { try? FileManager.default.removeItem(at: LocalPhotoStore.fileURL(photoID: photoID, userID: userID).deletingLastPathComponent()) }

        LocalPhotoStore.adopt(fileAt: pending, photoID: photoID, userID: userID)

        #expect(LocalPhotoStore.data(photoID: photoID, userID: userID) == bytes)
        #expect(!FileManager.default.fileExists(atPath: pending.path))
    }

    @Test func aPhotoIsOnlyFoundUnderItsOwner() throws {
        let photoID = UUID()
        let userID = UUID()
        let pending = FileManager.default.temporaryDirectory.appendingPathComponent("\(photoID).jpg")
        try Data("finished photo".utf8).write(to: pending)
        defer { try? FileManager.default.removeItem(at: LocalPhotoStore.fileURL(photoID: photoID, userID: userID).deletingLastPathComponent()) }

        LocalPhotoStore.adopt(fileAt: pending, photoID: photoID, userID: userID)

        #expect(LocalPhotoStore.data(photoID: photoID, userID: UUID()) == nil)
    }

    @Test func aFailedMoveStillClearsThePendingFile() throws {
        let pending = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).jpg")
        try Data().write(to: pending)
        // A user directory that can't be created, because a file is in the way.
        let userID = UUID()
        let blocker = LocalPhotoStore.fileURL(photoID: UUID(), userID: userID).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: blocker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        LocalPhotoStore.adopt(fileAt: pending, photoID: UUID(), userID: userID)

        #expect(!FileManager.default.fileExists(atPath: pending.path))
    }

    @Test func theLeastRecentlyOpenedGoFirst() {
        let now = Date.now
        let files = [
            file("newest", size: 40, lastUsed: now),
            file("oldest", size: 40, lastUsed: now.addingTimeInterval(-300)),
            file("middle", size: 40, lastUsed: now.addingTimeInterval(-100))
        ]
        #expect(LocalPhotoStore.filesToEvict(from: files, budget: 80).map(\.url.lastPathComponent) == ["oldest"])
        #expect(LocalPhotoStore.filesToEvict(from: files, budget: 40).map(\.url.lastPathComponent) == ["oldest", "middle"])
    }

    @Test func nothingGoesWithinBudget() {
        let files = [file("a", size: 40, lastUsed: .now), file("b", size: 40, lastUsed: .now)]
        #expect(LocalPhotoStore.filesToEvict(from: files, budget: 80).isEmpty)
    }

    private func file(_ name: String, size: Int, lastUsed: Date) -> LocalPhotoStore.StoredFile {
        LocalPhotoStore.StoredFile(url: URL(fileURLWithPath: "/\(name)"), size: size, lastUsed: lastUsed)
    }
}
