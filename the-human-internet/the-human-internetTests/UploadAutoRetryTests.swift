//
//  UploadAutoRetryTests.swift
//  the-human-internetTests
//

import Testing

@testable import the_human_internet

/// Pins the automatic retry schedule for failed uploads: 10s, 30s, 60s, then
/// nothing until the user taps "try again" —
/// which itself waits 15s after the last failure.
@MainActor
struct UploadAutoRetryTests {
    @Test func backsOffThenStops() {
        #expect(PhotoUploadQueue.autoRetryDelay(afterAttempts: 0) == .seconds(10))
        #expect(PhotoUploadQueue.autoRetryDelay(afterAttempts: 1) == .seconds(30))
        #expect(PhotoUploadQueue.autoRetryDelay(afterAttempts: 2) == .seconds(60))
        #expect(PhotoUploadQueue.autoRetryDelay(afterAttempts: 3) == nil)
    }

    @Test func manualRetryWaitsFifteenSeconds() {
        #expect(PhotoUploadQueue.manualRetryCooldown == .seconds(15))
    }
}
