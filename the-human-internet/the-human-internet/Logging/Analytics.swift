//
//  Analytics.swift
//  the-human-internet
//

import Foundation
import NewRelic

/// The one place the app tells New Relic *who* is using it. Everything else
/// the agent collects — session replay, crashes, HTTP traces — it picks up on
/// its own from the `NewRelic.start` call in `the_human_internetApp`.
///
/// Wrapped in a service rather than called inline so the New Relic import
/// stays out of `AppState`, the same way `AppleAuthService` and
/// `PhotoRepository` keep their SDKs out of the types that use them.
enum Analytics {
    /// The identifier the agent currently holds, so `setUserId` is only
    /// called when it genuinely changes.
    ///
    /// Not merely an optimisation. Per the SDK header, *changing* the user id
    /// starts a brand-new New Relic session — so re-sending the same username
    /// on every `AppState.user` mutation would shred one session into dozens.
    /// `refreshVerificationStatus` alone rewrites `user` every 5s for as long
    /// as a verification is pending.
    private static var reportedUserID: String?

    /// Associates this session's events with the signed-in person, so a
    /// session replay or crash reads as a recognisable user in the New Relic
    /// UI instead of a bare device.
    ///
    /// The username rather than `users.id` because the UUID identifies nobody
    /// at a glance — but note that this does hand the username to a third
    /// party, which the account UUID would not have.
    ///
    /// Passing `nil` (what sign-out does, via the empty `HumanUser`) both
    /// clears the association and starts a fresh session, so the next person
    /// on a shared device is never filed under the previous one.
    static func setUser(username: String?) {
        let trimmed = username?.trimmingCharacters(in: .whitespaces) ?? ""
        let identifier: String? = trimmed.isEmpty ? nil : trimmed

        guard identifier != reportedUserID else { return }
        reportedUserID = identifier

        if !NewRelic.setUserId(identifier) {
            Log.analytics.error("New Relic rejected the user id")
        }
    }
}
