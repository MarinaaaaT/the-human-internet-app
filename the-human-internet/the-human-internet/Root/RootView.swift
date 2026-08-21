//
//  RootView.swift
//  the-human-internet
//

import SwiftUI
import Supabase

struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var isRestoringSession = true
    @State private var showDeveloperMenu = false

    var body: some View {
        Group {
            if isRestoringSession {
                ZStack {
                    Theme.background.ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            } else if appState.isOnboarded {
                MainTabView()
            } else {
                OnboardingFlowView()
            }
        }
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            handle(url: url)
        }
        .background(
            // `appState.isAdmin` only ever becomes true post-hydrate (i.e.
            // once signed in), so this is naturally inert on Welcome/onboarding
            // screens for everyone but an already-onboarded admin.
            ShakeDetector {
                guard appState.isAdmin else { return }
                showDeveloperMenu = true
            }
        )
        .sheet(isPresented: $showDeveloperMenu) {
            DeveloperMenuView()
        }
        .fullScreenCover(item: Binding(
            get: { appState.deepLinkedPhoto },
            set: { appState.deepLinkedPhoto = $0 }
        )) { deepLink in
            PhotoVerificationView(photoID: deepLink.id)
        }
        .task {
            // Supabase persists the session (Keychain-backed) across launches on its own.
            // `.initialSession` fires once, right after the client attempts to restore
            // it — but the loop keeps running for the life of the view afterward, since
            // a session revoked elsewhere (or a failed background token refresh) shows
            // up later on this same stream as `.signedOut`, and otherwise went unnoticed:
            // the app just kept showing stale local state and failing every request.
            for await state in supabase.auth.authStateChanges {
                switch state.event {
                case .initialSession:
                    if let userID = state.session?.user.id {
                        await resolveProfile(userID: userID)
                    }
                    isRestoringSession = false
                case .signedOut:
                    // Ignore before the initial restore finishes — there's no prior
                    // session to have been revoked yet, and appState is already fresh.
                    guard !isRestoringSession else { continue }
                    appState.handleSessionInvalidated()
                default:
                    break
                }
            }
        }
    }

    /// Parses `thehumaninternet://photo/{id}`. Will swap to a Universal Link
    /// (`https://the-human-internet.com/{id}`) once the website hosts an
    /// apple-app-site-association file — this parsing/presentation logic stays
    /// the same either way.
    private func handle(url: URL) {
        guard url.scheme == VerifiedPhoto.deepLinkScheme,
              url.host == VerifiedPhoto.deepLinkHost else { return }
        guard let id = UUID(uuidString: url.lastPathComponent) else { return }
        appState.deepLinkedPhoto = DeepLinkedPhoto(id: id)
    }

    /// A restored session only proves the identity is authenticated — it doesn't say
    /// whether onboarding was ever finished. Hydrate their `users` row (and photos)
    /// so `isOnboarded` and any previously-entered fields reflect reality, not a
    /// fresh default.
    private func resolveProfile(userID: UUID) async {
        do {
            try await appState.hydrate(userID: userID)
        } catch {
            Log.auth.error("Hydrate failed for \(userID, privacy: .public): \(error, privacy: .public)")
            appState.user = HumanUser(id: userID)
            appState.isOnboarded = false
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
