//
//  FlowTriggersView.swift
//  the-human-internet
//

import SwiftUI

/// Manually kicks off flows that would otherwise only run once, mid-onboarding
/// — useful for testing without resetting a user's `onboarding_step` via SQL.
/// Restart Onboarding is that SQL reset, done from here.
struct FlowTriggersView: View {
    @Environment(AppState.self) private var appState
    @State private var isCreatingSession = false
    @State private var verificationURL: URL?
    @State private var errorMessage: String?
    @State private var isConfirmingRestart = false
    @State private var isRestartingOnboarding = false

    var body: some View {
        List {
            Section {
                Button {
                    startIdentityVerification()
                } label: {
                    HStack {
                        Text("Identity Verification")
                        if isCreatingSession {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isCreatingSession)
            } footer: {
                // Which environment this actually hits is decided server-side
                // by `stripe-identity-session`, from the same flag and the
                // same is_admin check — this only reports it.
                Text(
                    appState.isStripeIdentityTestModeEnabled
                        ? "Sessions are created in Stripe's test environment (sandbox)."
                        : "Sessions are created in Stripe's live environment."
                )
                .textStyle(DesignTokens.TextStyles.caption)
                .foregroundStyle(Theme.mutedForeground)
            }

            Section {
                Button {
                    isConfirmingRestart = true
                } label: {
                    HStack {
                        Text("Restart Onboarding")
                        if isRestartingOnboarding {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRestartingOnboarding)
            } footer: {
                Text("Starts again at profile setup, the step after Sign in with Apple. Photos, username and verification status are kept.")
                    .textStyle(DesignTokens.TextStyles.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Flow Triggers")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(
            isPresented: Binding(
                get: { verificationURL != nil },
                set: { if !$0 { verificationURL = nil } }
            )
        ) {
            if let verificationURL {
                // No-op completion: this runs for the current (already
                // onboarded) user, so there's no onboarding step to advance —
                // `verification_status` still updates later via the
                // stripe-identity-webhook Edge Function same as always.
                StripeIdentityWebView(url: verificationURL, onComplete: {})
            }
        }
        .confirmationDialog(
            "Restart onboarding?",
            isPresented: $isConfirmingRestart,
            titleVisibility: .visible
        ) {
            Button("Restart Onboarding") { restartOnboarding() }
        } message: {
            Text("You'll go through profile setup, identity verification and the welcome screen again. Nothing is deleted.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func startIdentityVerification() {
        isCreatingSession = true
        Task {
            do {
                switch try await UserProfileRepository.createIdentityVerificationSession() {
                case .hosted(let url):
                    verificationURL = url
                case .demoApproved:
                    // Only the demo account gets this, and it's never an
                    // admin — but if it ever were, there's nothing to show.
                    await appState.refreshVerificationStatus()
                }
            } catch {
                errorMessage = "Couldn't start verification — please try again."
                Log.devMenu.error("Creating identity verification session failed: \(error, privacy: .public)")
            }
            isCreatingSession = false
        }
    }

    /// RootView closes the developer menu once `isOnboarded` flips, so there's
    /// nothing to dismiss here on success.
    private func restartOnboarding() {
        isRestartingOnboarding = true
        Task {
            do {
                try await appState.restartOnboarding()
            } catch {
                errorMessage = "Couldn't restart onboarding — please try again."
                Log.devMenu.error("Restarting onboarding failed: \(error, privacy: .public)")
            }
            isRestartingOnboarding = false
        }
    }
}

#Preview {
    NavigationStack {
        FlowTriggersView()
            .environment(AppState())
    }
}
