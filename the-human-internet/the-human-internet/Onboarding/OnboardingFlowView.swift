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
                    // Admin-controlled (developer menu > Feature Flags >
                    // "Show Stripe Identity Verification"). Off ⇒ the step
                    // isn't shown at all and `skipVerification` takes the
                    // user through it on exactly the terms a manual Skip
                    // would have.
                    if appState.isStripeIdentityVerificationEnabled {
                        // Both paths advance: verification is optional, so
                        // skipping is a legitimate way through the step. The
                        // difference is what `verificationStatus` is left at,
                        // which these two set and `advance` persists in the
                        // same upsert as the step itself.
                        IdentityVerificationView(
                            onSkip: { skipVerification() },
                            onFinish: { advance(to: .welcomeHuman) }
                        )
                    } else {
                        ZStack {
                            Theme.background.ignoresSafeArea()
                            ProgressView().tint(.white)
                        }
                        .onAppear { skipVerification() }
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

    /// The two ways past the verify step without submitting anything —
    /// tapping Skip, and the step being switched off by the feature flag —
    /// have to leave a user in exactly the same place, so both come through
    /// here. Stating `.unverified` outright is what makes them identical,
    /// rather than each relying separately on it being the column default;
    /// `advance` then persists it in the same upsert as the step.
    ///
    /// In practice this can only ever write `unverified` over `unverified`:
    /// `prevent_self_verification_escalation` silently reverts every
    /// client-side change to the column except `unverified -> in_progress`.
    /// So it asserts a resting state — it is not, and cannot become, a way
    /// to undo a real `verified`. That still needs the webhook or another
    /// service_role caller.
    private func skipVerification() {
        appState.user.verificationStatus = .unverified
        advance(to: .welcomeHuman)
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
