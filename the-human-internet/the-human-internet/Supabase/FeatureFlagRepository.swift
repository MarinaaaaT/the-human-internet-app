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
    /// Whether onboarding offers the Stripe Identity step — the developer
    /// menu's "ID Verification in Onboarding". Off ⇒ `OnboardingFlowView`
    /// skips the step and the user comes out `unverified`, exactly as if
    /// they'd tapped Skip.
    ///
    /// Split from `stripe_identity_verification` (which gated onboarding and
    /// Settings together) on 2026-10-25, so the two doors can be opened and
    /// closed separately. That row stays in the table for builds that still
    /// read it; this build doesn't.
    static let identityVerificationOnboarding = "identity_verification_onboarding"
    /// Whether Profile settings offers identity verification — the
    /// developer menu's "ID Verification in Settings". Off ⇒ no Verify
    /// identity button and no pitch for it, and the Identity verification
    /// row is hidden too while the user is `unverified` (with nothing to act
    /// on, "Not verified" only advertises a door that's shut). Any other
    /// status still shows, since it stays true either way.
    static let identityVerificationSettings = "identity_verification_settings"
    /// Whether this user's verification sessions are created against
    /// Stripe's test environment instead of live. Switched from the
    /// developer tools rather than the feature flags page, and admin-only by
    /// construction — see `DeveloperToolsView` and
    /// `AppState.isStripeIdentityTestModeEnabled`, and note that the
    /// binding check is the one `stripe-identity-session` makes server-side.
    ///
    /// Still a remote flag, not a local setting, precisely because of that
    /// server-side check: the Edge Function reads this row to pick a Stripe
    /// key, so a device-only switch would change nothing.
    static let stripeIdentityTestMode = "stripe_identity_test_mode"
    /// Whether text is set in PP Neue Montreal instead of Inter Display —
    /// the developer menu's "Neue Font: Pay To Enable".
    ///
    /// **This flag is the font licence switch.** The Neue Montreal files we
    /// hold are the free-for-personal-use release, so they aren't bundled
    /// (the repo is public); `Typography` downloads them from the private
    /// `licensed-fonts` bucket, and that bucket's storage policy resolves
    /// this same flag. `admin` = an admin evaluating it on their own device.
    /// `all` hands the files to every user *and* to the website (which reads
    /// it via `public_feature_flag_enabled`) — set it only once a commercial
    /// licence is bought and the paid files have replaced the free ones.
    static let neueFont = "neue_font"

    /// What a flag falls back to when the server has nothing this build can
    /// use: the row is missing, the flags never loaded, or the audience is a
    /// string this build doesn't recognise.
    ///
    /// All of them land on `.off` today, but this stays a per-flag switch
    /// rather than collapsing into one shared default: the safe direction is
    /// a property of what a given flag guards, not of flags in general.
    /// `stripe_identity_verification` fell back to `.all` for exactly that
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
        // stranded: Settings can offer verification again later.
        case identityVerificationOnboarding: return .off
        // Off ⇒ Settings stops offering it. A user who already has a status
        // other than `unverified` still sees it.
        case identityVerificationSettings: return .off
        // Never fall *into* the sandbox. A test-environment verification
        // proves nothing about a real person, so it has to be switched on
        // deliberately, by an admin, every time.
        case stripeIdentityTestMode: return .off
        // Inter Display is bundled and always works; the files this flag
        // fetches are licence-restricted.
        case neueFont: return .off
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
