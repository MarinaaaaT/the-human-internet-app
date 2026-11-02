//
//  PhotoReportTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// Pins `PhotoReportReason` against `photo_reports.reason`'s CHECK
/// constraint (the backend's `supabase/sql/2026-11-01_photo_reports.sql`).
/// The app only writes that column, so a reason the database doesn't list
/// fails the insert and the user sees "Couldn't send your report" for a
/// report that can never go through.
struct PhotoReportTests {
    /// Copied from the CHECK constraint. Change both together.
    static let databaseReasons: Set<String> = [
        "not_real",
        "sexual",
        "violent",
        "harassment",
        "privacy",
        "other",
    ]

    @Test func everyReasonIsOneTheDatabaseAccepts() {
        #expect(Set(PhotoReportReason.allCases.map(\.rawValue)) == Self.databaseReasons)
    }

    @Test func everyReasonHasATitle() {
        for reason in PhotoReportReason.allCases {
            #expect(!reason.title.isEmpty)
        }
    }
}
