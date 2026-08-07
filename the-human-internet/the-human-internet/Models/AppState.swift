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

    /// IDs of photos in `photos` whose upload to Supabase is still in
    /// flight (optimistically inserted, not yet confirmed) or has failed and
    /// is waiting on a retry. Driven by `PhotoUploadQueue`; views read these
    /// to show a spinner/retry badge without blocking capture on the network.
    var uploadingPhotoIDs: Set<UUID> = []
    var failedUploadIDs: Set<UUID> = []

    /// Set from a `thehumaninternet://photo/{id}` link. Drives a root-level
    /// fullScreenCover so it can present over whatever's currently on screen —
    /// dismissing it clears this, so the link has to be tapped again to reopen it.
    var deepLinkedPhoto: DeepLinkedPhoto?

    /// Clears local state after Supabase signs out, so RootView's isOnboarded
    /// check naturally falls back to OnboardingFlowView's Welcome screen.
    func signOut() async throws {
        try await supabase.auth.signOut()
        isOnboarded = false
        user = HumanUser()
        photos = []
        uploadingPhotoIDs = []
        failedUploadIDs = []
        deepLinkedPhoto = nil
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
