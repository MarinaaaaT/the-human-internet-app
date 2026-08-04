//
//  RootView.swift
//  the-human-internet
//

import SwiftUI
import Supabase

struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var isRestoringSession = true

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
        .task {
            // Supabase persists the session (Keychain-backed) across launches on its own.
            // `.initialSession` fires once, right after the client attempts to restore it.
            for await state in supabase.auth.authStateChanges where state.event == .initialSession {
                if let userID = state.session?.user.id {
                    await resolveProfile(userID: userID)
                }
                isRestoringSession = false
                break
            }
        }
    }

    /// A restored session only proves the identity is authenticated — it doesn't say
    /// whether onboarding was ever finished. Fetch (or create) their `users` row so
    /// `isOnboarded` and any previously-entered fields reflect reality, not a fresh default.
    private func resolveProfile(userID: UUID) async {
        do {
            let profile = try await UserProfileRepository.resolveOrCreate(userID: userID)
            appState.user = profile
            appState.isOnboarded = profile.onboardingStep == .completed
        } catch {
            debugPrint(error)
            appState.user = HumanUser(id: userID)
            appState.isOnboarded = false
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
