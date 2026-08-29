//
//  FeatureFlagRepository.swift
//  the-human-internet
//

import Foundation
import Supabase

/// Remote, server-backed flags — not a local/per-device toggle. Changing one
/// (e.g. from the developer menu) changes behavior for every user, not just
/// the admin's own device. Writes are enforced admin-only by RLS on
/// `public.feature_flags`.
enum FeatureFlagKey {
    /// Whether onboarding offers the Stripe Identity step at all — the
    /// developer menu's "Show Stripe Identity Verification".
    static let stripeIdentityVerification = "stripe_identity_verification"
    /// Whether this user's verification sessions are created against
    /// Stripe's test environment instead of live. Admin-only by
    /// construction — see `FeatureFlagPolicy` and
    /// `AppState.isStripeIdentityTestModeEnabled`, and note that the
    /// binding check is the one `stripe-identity-session` makes server-side.
    static let stripeIdentityTestMode = "stripe_identity_test_mode"
    static let awsServerSideSigning = "aws_server_side_signing"

    /// What a flag falls back to when the server has nothing this build can
    /// use: the row is missing, the flags never loaded, or the audience is a
    /// string this build doesn't recognise.
    ///
    /// All three land on `.off` today, but this stays a per-flag switch
    /// rather than collapsing into one shared default: the safe direction is
    /// a property of what a given flag guards, not of flags in general.
    /// `stripeIdentityVerification` fell back to `.all` for exactly that
    /// reason while the verify step was mandatory — failing open would have
    /// waved a whole cohort past it — and only became `.off` once
    /// verification turned optional and a skipped step stopped meaning
    /// anything was lost. An unknown key defaults to `.off`, since a flag
    /// this build has never heard of is by definition guarding something it
    /// doesn't implement.
    static func fallbackAudience(for key: String) -> FeatureFlagAudience {
        switch key {
        // Off ⇒ onboarding skips the step and the user comes out
        // `unverified`, exactly as if they'd tapped Skip. Nothing is
        // stranded: Settings offers verification again later.
        case stripeIdentityVerification: return .off
        // Never fall *into* the sandbox. A test-environment verification
        // proves nothing about a real person, so it has to be switched on
        // deliberately, by an admin, every time.
        case stripeIdentityTestMode: return .off
        // Remote signing is opt-in while it's being stood up, not somewhere
        // to end up by accident.
        case awsServerSideSigning: return .off
        default: return .off
        }
    }
}

/// Who a flag is switched on for. Mirrors the `feature_flags_audience_check`
/// constraint on `public.feature_flags`.
///
/// Replaces a plain boolean so a change can be dark-launched: `admin` runs
/// the new path for admin accounts only, which is how it gets exercised
/// against real production data without exposing it to everyone at once.
enum FeatureFlagAudience: String, CaseIterable, Identifiable, Codable, Hashable {
    /// On for everyone.
    case all
    /// On only for users whose `users.is_admin` is true.
    case admin
    /// Off for everyone.
    case off

    var id: String { rawValue }

    /// The developer menu's picker labels.
    var label: String {
        switch self {
        case .all: return "All"
        case .admin: return "Admin"
        case .off: return "Off"
        }
    }

    /// Resolves an audience against *this* user — the whole reason the enum
    /// exists. `isAdmin` comes from `AppState`, which sources it from the
    /// read-only `UserProfileRepository.fetchIsAdmin` and never from a field
    /// the client can write back to its own row.
    func includes(isAdmin: Bool) -> Bool {
        switch self {
        case .all: return true
        case .admin: return isAdmin
        case .off: return false
        }
    }
}

/// Constraints on what a flag may be set *to*, checked before the developer
/// menu writes anything.
///
/// Lives here rather than inside `FeatureFlagsView` so it can be tested
/// without a view — the same reason `StripeIdentityHostPolicy` sits outside
/// the web view it guards. This is a UI guard, not a security boundary: the
/// database will happily store `all` on any flag, so anything that actually
/// matters has to be enforced where it's read (`AppState`) and server-side
/// (the `stripe-identity-session` Edge Function), which is where the test
/// environment is really gated.
enum FeatureFlagPolicy {
    /// Why `audience` can't be applied to `key`, or `nil` if it can.
    static func rejectionReason(setting key: String, to audience: FeatureFlagAudience) -> String? {
        guard key == FeatureFlagKey.stripeIdentityTestMode, audience == .all else { return nil }
        return "Non-admins should not be allowed to verify identity with Stripe sandbox."
    }
}

enum FeatureFlagRepository {
    /// `audience` is decoded as a plain `String` and mapped afterwards
    /// instead of being decoded straight into `FeatureFlagAudience`. An
    /// audience this build doesn't recognise then drops out of the dictionary
    /// entirely and `FeatureFlagKey.fallbackAudience(for:)` applies — which
    /// is what we want, since the safe direction differs per flag and one
    /// enum-level fallback couldn't be right for both.
    ///
    /// It also means an unrecognised value can't throw, which matters more
    /// than it looks: this runs inside `AppState.hydrate`, where a decoding
    /// error takes sign-in down with it. Compare `DatabaseEnum` in
    /// `Models.swift`, which solves the same problem for the enums that
    /// *are* decoded directly.
    private struct Row: Decodable {
        let key: String
        let audience: String
    }

    static func fetchAll() async throws -> [String: FeatureFlagAudience] {
        let rows: [Row] = try await supabase
            .from("feature_flags")
            .select("key,audience")
            .execute()
            .value

        var flags: [String: FeatureFlagAudience] = [:]
        for row in rows {
            guard let audience = FeatureFlagAudience(rawValue: row.audience) else {
                Log.devMenu.error(
                    "Unrecognised audience '\(row.audience, privacy: .public)' on feature flag \(row.key, privacy: .public) — using this build's fallback"
                )
                continue
            }
            flags[row.key] = audience
        }
        return flags
    }

    /// Only `audience` is written. The table's `enabled` column still exists
    /// for builds shipped before the audience column did, but it's generated
    /// from `audience` now and rejects writes — one value, one place.
    static func setAudience(key: String, audience: FeatureFlagAudience) async throws {
        try await supabase
            .from("feature_flags")
            .update(["audience": audience.rawValue])
            .eq("key", value: key)
            .execute()
    }
}
