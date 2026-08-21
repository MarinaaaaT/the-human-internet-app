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
    var user = HumanUser()
    var photos: [VerifiedPhoto] = []

    /// Never sourced from `user`/`HumanUser` — see
    /// `UserProfileRepository.fetchIsAdmin` for why admin status is kept out
    /// of the model that round-trips through `upsert`.
    var isAdmin = false

    /// Remote feature flags, keyed by `FeatureFlagKey`. Populated on every
    /// hydrate so a flag flipped by an admin takes effect for other users on
    /// their next launch/sign-in without an app update.
    var featureFlags: [String: Bool] = [:]

    /// Fails secure: if flags haven't loaded (or the key is missing), this
    /// defaults to `true` — same as verification being required today —
    /// rather than silently letting onboarding skip a step on a fetch glitch.
    var isStripeIdentityVerificationEnabled: Bool {
        featureFlags[FeatureFlagKey.stripeIdentityVerification] ?? true
    }

    /// Fails secure the other direction from the flag above: defaults to
    /// `false` (on-device signing) if flags haven't loaded, since the AWS
    /// signing path is opt-in while it's being stood up, not a fallback to
    /// avoid depending on.
    var isAWSServerSideSigningEnabled: Bool {
        featureFlags[FeatureFlagKey.awsServerSideSigning] ?? false
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
    func handleSessionInvalidated() {
        isOnboarded = false
        user = HumanUser()
        photos = []
        processingPhotoIDs = []
        failedPhotoIDs = []
        deepLinkedPhoto = nil
        isAdmin = false
        featureFlags = [:]
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
