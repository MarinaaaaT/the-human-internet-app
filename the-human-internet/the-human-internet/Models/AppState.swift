//
//  AppState.swift
//  the-human-internet
//

import SwiftUI
import Observation
import Supabase

@Observable
final class AppState {
    var isOnboarded = false

    /// Assigned from every path that can change who is signed in or what
    /// they're called — `hydrate`, `handleSessionInvalidated`, the onboarding
    /// profile step, and the Settings username sheet — which is why the
    /// New Relic association hangs off `didSet` here rather than being
    /// repeated at all four call sites. Four copies of that call is exactly
    /// the shape that let the old duplicated sign-in logic drift apart.
    ///
    /// `Analytics.setUser` no-ops when the username hasn't actually changed,
    /// so the frequent whole-row writes (`refreshVerificationStatus`) cost
    /// nothing.
    var user = HumanUser() {
        didSet { Analytics.setUser(username: user.username) }
    }

    var photos: [VerifiedPhoto] = []

    /// Never sourced from `user`/`HumanUser` — see
    /// `UserProfileRepository.fetchIsAdmin` for why admin status is kept out
    /// of the model that round-trips through `upsert`.
    var isAdmin = false

    /// Remote feature flags, keyed by `FeatureFlagKey`. Populated on every
    /// hydrate so a flag changed by an admin takes effect for other users on
    /// their next launch/sign-in without an app update.
    ///
    /// An audience rather than a bool, so a flag can be switched on for admin
    /// accounts only — see `FeatureFlagAudience`. A key absent here means the
    /// server had nothing this build could use for it, and
    /// `FeatureFlagKey.fallbackAudience(for:)` decides what that means.
    var featureFlags: [String: FeatureFlagAudience] = [:]

    /// The audience a flag currently carries — the *unresolved* server value,
    /// which is what the developer menu's picker shows and edits. Use the
    /// `is…Enabled` properties below to ask whether a flag is on for the
    /// person actually using the app.
    func audience(for key: String) -> FeatureFlagAudience {
        featureFlags[key] ?? FeatureFlagKey.fallbackAudience(for: key)
    }

    /// Writes a flag's audience from the developer menu. Optimistic,
    /// revert-on-failure — same pattern as `OnboardingFlowView.advance(to:)`.
    /// `FeatureFlagRepository` is restricted to admins by RLS, so a failure
    /// here most likely means `isAdmin` is stale.
    ///
    /// Reverting assigns the previous `FeatureFlagAudience?` back, so a flag
    /// that was never in the dictionary returns to being absent rather than
    /// getting pinned to whatever fallback the UI happened to display.
    func setAudience(_ audience: FeatureFlagAudience, for key: String) async throws {
        let previous = featureFlags[key]
        featureFlags[key] = audience
        do {
            try await FeatureFlagRepository.setAudience(key: key, audience: audience)
        } catch {
            featureFlags[key] = previous
            throw error
        }
    }

    /// Resolves a flag against this user. `.admin` reads `isAdmin`, which
    /// `hydrate` fetches *before* the flags, so the two are never out of step.
    private func isEnabled(_ key: String) -> Bool {
        audience(for: key).includes(isAdmin: isAdmin)
    }

    /// Whether onboarding shows the Stripe Identity step at all. Off ⇒
    /// `OnboardingFlowView` skips it and leaves the user `unverified`,
    /// identically to their tapping Skip — see
    /// `OnboardingFlowView.skipVerification()`.
    var isStripeIdentityVerificationEnabled: Bool {
        isEnabled(FeatureFlagKey.stripeIdentityVerification)
    }

    /// Whether this user's verification sessions run against Stripe's test
    /// environment instead of live.
    ///
    /// Admin-gated twice over, deliberately. A sandbox verification proves
    /// nothing about a real person, so it must never be what a real user
    /// gets: the developer tools' switch only ever writes `.admin` or `.off`
    /// (`DeveloperToolsView`), and the `isAdmin` conjunct here means a value
    /// written around that UI — direct SQL, some future build — still can't
    /// reach a non-admin. Neither is load-bearing on its own: the check that
    /// binds is the identical one `stripe-identity-session` makes server-side
    /// before it picks a Stripe key. This property only decides what the app
    /// *shows*.
    var isStripeIdentityTestModeEnabled: Bool {
        isAdmin && isEnabled(FeatureFlagKey.stripeIdentityTestMode)
    }

    /// The developer tools' "Skip C2PA verification" switch, as stored on
    /// *this device* — unlike the feature flags above it's never written to
    /// the server, so one admin testing with it can't change what another
    /// admin's uploads carry. Read `isC2PASigningSkipped`, never this, to
    /// decide whether to sign.
    var skipC2PASigningPreference = UserDefaults.standard.bool(forKey: AppState.skipC2PASigningDefaultsKey) {
        didSet { UserDefaults.standard.set(skipC2PASigningPreference, forKey: Self.skipC2PASigningDefaultsKey) }
    }
    private static let skipC2PASigningDefaultsKey = "devTools.skipC2PASigning"

    /// Whether `PhotoUploadQueue` uploads photos watermarked but unsigned,
    /// with no C2PA manifest. The `isAdmin` conjunct is what keeps the
    /// preference from outliving the admin who set it: it's per-device, so a
    /// non-admin signing in on the same phone would otherwise inherit it and
    /// publish photos that make no provenance claim at all.
    var isC2PASigningSkipped: Bool {
        isAdmin && skipC2PASigningPreference
    }

    /// Whether Settings offers the verification-page editor to a verified
    /// user.
    ///
    /// Like `isStripeIdentityVerificationEnabled`, this only decides what the
    /// app *shows*. The switch that binds is server-side: the same flag is
    /// resolved inside `get_verification_photo()` against the photo's owner,
    /// so turning it off stops already-saved names and handles from being
    /// published too — which is the half a client-side check could never do.
    var isCustomVerificationPagesEnabled: Bool {
        isEnabled(FeatureFlagKey.customVerificationPages)
    }

    /// IDs of photos in `photos` that are still being signed and/or
    /// uploaded to Supabase (optimistically inserted, not yet confirmed) or
    /// have failed and are waiting on a retry. Driven by `PhotoUploadQueue`;
    /// views read these to show a spinner/retry badge without blocking
    /// capture on signing or the network.
    var processingPhotoIDs: Set<UUID> = []
    var failedPhotoIDs: Set<UUID> = []

    /// Collapses the two ID sets above into the single state a photo tile
    /// renders, so views receive a value instead of reaching into `AppState`
    /// and re-deriving the same precedence themselves.
    func uploadState(for photoID: UUID) -> PhotoUploadState {
        if processingPhotoIDs.contains(photoID) { return .processing }
        if failedPhotoIDs.contains(photoID) { return .failed }
        return .idle
    }

    /// Set from a `thehumaninternet://photo/{id}` link. Drives a root-level
    /// fullScreenCover so it can present over whatever's currently on screen —
    /// dismissing it clears this, so the link has to be tapped again to reopen it.
    var deepLinkedPhoto: DeepLinkedPhoto?

    /// Clears local state after Supabase signs out, so RootView's isOnboarded
    /// check naturally falls back to OnboardingFlowView's Welcome screen.
    ///
    /// Prunes this user's un-uploaded photos from disk first — before the
    /// network call, so the local cleanup still happens even if signing out
    /// of Supabase fails — so the next person on a shared device can't
    /// recover them.
    func signOut() async throws {
        if let userID = user.id {
            await PhotoUploadQueue.pruneOnSignOut(userID: userID)
        }
        try await supabase.auth.signOut()
        handleSessionInvalidated()
    }

    /// Called when a previously-restored session goes invalid on its own —
    /// revoked from another device, or a background token refresh failing —
    /// rather than through an explicit user-initiated `signOut()`. Resets
    /// the same local state `signOut()` does so RootView's `isOnboarded`
    /// check falls back to the Welcome screen, but deliberately does
    /// *not* call `PhotoUploadQueue.pruneOnSignOut`: this is still the same
    /// person on the same device, just needing to re-authenticate, and the
    /// pending-upload manifest already knows how to resume once they do.
    ///
    /// Decoded grid thumbnails *are* dropped, though — those are the previous
    /// user's photo contents sitting in memory, and leaving them for whoever
    /// signs in next would undo what `pruneOnSignOut` does for disk.
    func handleSessionInvalidated() {
        PhotoThumbnailCache.removeAll()
        isOnboarded = false
        user = HumanUser()
        photos = []
        processingPhotoIDs = []
        failedPhotoIDs = []
        deepLinkedPhoto = nil
        isAdmin = false
        featureFlags = [:]
    }

    /// Pulls the current `verification_status` down onto `user`, leaving the
    /// rest of the row alone. Best-effort by design: this runs on foregrounding
    /// and on a timer, where a failed read should cost nothing and simply be
    /// retried on the next tick rather than surfacing an alert.
    ///
    /// Deliberately not a `hydrate`. That refetches photos and resumes uploads,
    /// and its `photos = fetchAll(...)` would briefly drop optimistically
    /// inserted pending captures — fine at launch, wrong on every return to
    /// the foreground.
    func refreshVerificationStatus() async {
        guard let userID = user.id else { return }
        do {
            let status = try await UserProfileRepository.fetchVerificationStatus(userID: userID)
            if status != user.verificationStatus {
                Log.onboarding.info(
                    "Verification status changed to \(status.rawValue, privacy: .public)"
                )
                user.verificationStatus = status
            }
        } catch {
            Log.onboarding.error("Refreshing verification status failed: \(error, privacy: .public)")
        }
    }

    /// The single place that turns "this identity is authenticated" into
    /// "here's their profile, their photos, and whether onboarding is done."
    /// Called from both RootView (restoring a session at cold launch) and
    /// OnboardingFlowView (right after a fresh sign-in) — previously each had
    /// its own copy of this and they drifted: only RootView's version fetched
    /// photos, and neither correctly short-circuited a returning, already-
    /// onboarded user straight past the onboarding screens.
    func hydrate(userID: UUID) async throws {
        let profile = try await UserProfileRepository.resolveOrCreate(userID: userID)
        user = profile
        isOnboarded = profile.onboardingStep == .completed
        isAdmin = try await UserProfileRepository.fetchIsAdmin(userID: userID)
        featureFlags = try await FeatureFlagRepository.fetchAll()
        photos = try await PhotoRepository.fetchAll(userID: userID)
        // Picks back up anything left mid-upload by a force-quit or crash —
        // safe to call on every hydrate, since PhotoUploadQueue no-ops for
        // an id it's already driving.
        await PhotoUploadQueue.resumePendingUploads(userID: userID, appState: self)
    }
}

struct DeepLinkedPhoto: Identifiable, Equatable {
    let id: UUID
}
