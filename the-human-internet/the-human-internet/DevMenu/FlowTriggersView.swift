//
//  FlowTriggersView.swift
//  the-human-internet
//

import SwiftUI

/// Manually kicks off flows that would otherwise only run once, mid-onboarding
/// — useful for testing without resetting a user's `onboarding_step` via SQL.
struct FlowTriggersView: View {
    @State private var isCreatingSession = false
    @State private var verificationURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        List {
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
                verificationURL = try await UserProfileRepository.createIdentityVerificationSession()
            } catch {
                errorMessage = "Couldn't start verification — please try again."
                Log.devMenu.error("Creating identity verification session failed: \(error, privacy: .public)")
            }
            isCreatingSession = false
        }
    }
}

#Preview {
    NavigationStack {
        FlowTriggersView()
            .environment(AppState())
    }
}
