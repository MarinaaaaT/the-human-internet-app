//
//  OnboardingFlowView.swift
//  the-human-internet
//

import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppState.self) private var appState
    @State private var path: [OnboardingStep] = []
    @State private var authService = AppleAuthService()
    @State private var authErrorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(isBusy: authService.isAuthenticating) { request in
                authService.configure(request)
            } onCompletion: { result in
                Task {
                    do {
                        try await authService.handle(result)
                        let userID = try await supabase.auth.session.user.id
                        try await appState.hydrate(userID: userID)
                        // A returning, already-onboarded user: `appState.isOnboarded`
                        // is now true, so RootView swaps straight to MainTabView —
                        // no need to push anything here.
                        if !appState.isOnboarded {
                            path = Self.resumePath(for: appState.user)
                        }
                    } catch {
                        authErrorMessage = error.localizedDescription
                    }
                }
            }
            .navigationDestination(for: OnboardingStep.self) { step in
                switch step {
                case .profile:
                    ProfileSetupView {
                        advance(to: .verify)
                    }
                case .verify:
                    // Admin-controlled kill switch (developer menu > Feature
                    // Flags) for when Stripe Identity itself is unavailable —
                    // skips straight through, leaving verification_status at
                    // its default (pending) rather than getting users stuck.
                    if appState.isStripeIdentityVerificationEnabled {
                        IdentityVerificationView {
                            advance(to: .welcomeHuman)
                        }
                    } else {
                        ZStack {
                            Theme.background.ignoresSafeArea()
                            ProgressView().tint(.white)
                        }
                        .onAppear { advance(to: .welcomeHuman) }
                    }
                case .welcomeHuman:
                    WelcomeHumanView {
                        advance(to: .completed)
                    }
                case .completed:
                    EmptyView()
                }
            }
        }
        .onAppear {
            // If we already resolved a mid-onboarding profile (e.g. RootView found a
            // signed-in-but-incomplete user), jump straight to where they left off
            // instead of showing the sign-in screen again.
            if path.isEmpty {
                path = Self.resumePath(for: appState.user)
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { authErrorMessage != nil },
                set: { if !$0 { authErrorMessage = nil } }
            )
        ) {
            Button("OK") { authErrorMessage = nil }
        } message: {
            Text(authErrorMessage ?? "")
        }
    }

    /// Upserts before navigating — if the save fails (e.g. a username conflict
    /// picked up during `.profile`), the step reverts instead of moving on with
    /// unsaved data.
    private func advance(to step: OnboardingStep) {
        let previousStep = appState.user.onboardingStep
        appState.user.onboardingStep = step

        Task {
            do {
                try await UserProfileRepository.upsert(appState.user)
                if step == .completed {
                    appState.isOnboarded = true
                } else {
                    path.append(step)
                }
            } catch {
                appState.user.onboardingStep = previousStep
                authErrorMessage = UserProfileRepository.isUsernameConflict(error)
                    ? "That username is already taken."
                    : "Couldn't save — please try again."
                Log.onboarding.error("Saving onboarding step failed: \(error, privacy: .public)")
            }
        }
    }

    /// Only called for users who aren't fully onboarded — `appState.hydrate`
    /// already routes a `.completed` user straight to MainTabView before this
    /// runs. `.completed` is handled below only as a defensive fallback.
    private static func resumePath(for user: HumanUser) -> [OnboardingStep] {
        guard user.id != nil else { return [] }
        switch user.onboardingStep {
        case .profile: return [.profile]
        case .verify: return [.verify]
        case .welcomeHuman, .completed: return [.welcomeHuman]
        }
    }
}

#Preview {
    OnboardingFlowView()
        .environment(AppState())
}
