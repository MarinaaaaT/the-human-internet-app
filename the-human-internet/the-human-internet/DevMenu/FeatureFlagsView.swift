//
//  FeatureFlagsView.swift
//  the-human-internet
//

import SwiftUI

struct FeatureFlagsView: View {
    @Environment(AppState.self) private var appState
    @State private var errorMessage: String?

    var body: some View {
        List {
            Toggle(
                "Stripe Identity Verification",
                isOn: Binding(
                    get: { appState.isStripeIdentityVerificationEnabled },
                    set: { setFlag(FeatureFlagKey.stripeIdentityVerification, to: $0) }
                )
            )
            Toggle(
                "AWS Server Side Signing",
                isOn: Binding(
                    get: { appState.isAWSServerSideSigningEnabled },
                    set: { setFlag(FeatureFlagKey.awsServerSideSigning, to: $0) }
                )
            )
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Feature Flags")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Couldn't update flag",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    /// Optimistic, revert-on-failure — same pattern as
    /// `OnboardingFlowView.advance(to:)`. This writes through
    /// `FeatureFlagRepository`, which RLS restricts to admins only, so a
    /// failure here most likely means `appState.isAdmin` is stale.
    private func setFlag(_ key: String, to enabled: Bool) {
        let previous = appState.featureFlags[key]
        appState.featureFlags[key] = enabled
        Task {
            do {
                try await FeatureFlagRepository.setEnabled(key: key, enabled: enabled)
            } catch {
                appState.featureFlags[key] = previous
                errorMessage = "Please try again."
                Log.devMenu.error("Setting feature flag \(key, privacy: .public) failed: \(error, privacy: .public)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        FeatureFlagsView()
            .environment(AppState())
    }
}
