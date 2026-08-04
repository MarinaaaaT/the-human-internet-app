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
                        let profile = try await UserProfileRepository.resolveOrCreate(userID: userID)
                        appState.user = profile
                        path = Self.resumePath(for: profile)
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
                    IdentityVerificationView {
                        advance(to: .welcomeHuman)
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
                debugPrint(error)
            }
        }
    }

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
