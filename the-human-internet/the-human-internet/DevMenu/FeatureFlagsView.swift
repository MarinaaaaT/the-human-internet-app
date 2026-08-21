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
            Section {
                flagPicker("Stripe Identity Verification", key: FeatureFlagKey.stripeIdentityVerification)
                flagPicker("AWS Server Side Signing", key: FeatureFlagKey.awsServerSideSigning)
            } footer: {
                Text("All: on for every user. Admin: on only for admin accounts — use it to try a change against real data before everyone gets it. Off: on for nobody.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
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

    /// Reads `audience(for:)` rather than the resolved `is…Enabled` bool: the
    /// picker edits what the *server* holds, which for an `.admin` flag isn't
    /// the same thing as whether it's on for whoever is looking at it.
    private func flagPicker(_ title: String, key: String) -> some View {
        Picker(
            title,
            selection: Binding(
                get: { appState.audience(for: key) },
                set: { setAudience(key, to: $0) }
            )
        ) {
            ForEach(FeatureFlagAudience.allCases) { audience in
                Text(audience.label).tag(audience)
            }
        }
        .pickerStyle(.menu)
        .tint(Theme.accentBlue)
    }

    /// Optimistic, revert-on-failure — same pattern as
    /// `OnboardingFlowView.advance(to:)`. This writes through
    /// `FeatureFlagRepository`, which RLS restricts to admins only, so a
    /// failure here most likely means `appState.isAdmin` is stale.
    ///
    /// Reverting assigns the previous `FeatureFlagAudience?` back, so a flag
    /// that was never in the dictionary returns to being absent rather than
    /// getting pinned to whatever fallback the picker happened to display.
    private func setAudience(_ key: String, to audience: FeatureFlagAudience) {
        let previous = appState.featureFlags[key]
        appState.featureFlags[key] = audience
        Task {
            do {
                try await FeatureFlagRepository.setAudience(key: key, audience: audience)
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
