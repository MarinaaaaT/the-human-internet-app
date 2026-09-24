//
//  DeveloperToolsView.swift
//  the-human-internet
//

import SwiftUI

/// On/off switches that bend the app for an admin who's testing it, as
/// opposed to `FeatureFlagsView`, which changes what every user gets.
struct DeveloperToolsView: View {
    @Environment(AppState.self) private var appState
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var appState = appState

        List {
            DevMenuDescription(
                "These capabilities are only available to admins. Please disable all capabilities when testing the real user experience."
            )

            Section {
                Toggle(isOn: testModeBinding) {
                    Text("Use Test Environment for Stripe Identity Verification")
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                footer("Creates verification sessions in Stripe's sandbox instead of live. Applies to every admin account, not just this device — the server reads it to pick a Stripe key.")
            }

            Section {
                Toggle(isOn: $appState.skipC2PASigningPreference) {
                    Text("Skip C2PA verification")
                }
            } footer: {
                footer("New photos are watermarked and uploaded as usual but not signed, so they carry no C2PA manifest. This device only.")
            }
        }
        .tint(Theme.accentBlue)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Developer Tools")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Couldn't update setting",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    /// Still the remote `stripe_identity_test_mode` flag underneath, since
    /// `stripe-identity-session` reads it server-side. On writes `.admin`,
    /// never `.all` — a sandbox verification proves nothing about a real
    /// person, so a switch has no way to express "everyone". The same
    /// `.admin` reading is why this shows the *resolved* value: for an admin
    /// it's on exactly when the server has `.admin` (or a stray `.all`).
    private var testModeBinding: Binding<Bool> {
        Binding(
            get: { appState.isStripeIdentityTestModeEnabled },
            set: { isOn in
                let key = FeatureFlagKey.stripeIdentityTestMode
                Task {
                    do {
                        try await appState.setAudience(isOn ? .admin : .off, for: key)
                    } catch {
                        errorMessage = "Please try again."
                        Log.devMenu.error("Setting feature flag \(key, privacy: .public) failed: \(error, privacy: .public)")
                    }
                }
            }
        )
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
    }
}

#Preview {
    NavigationStack {
        DeveloperToolsView()
            .environment(AppState())
    }
}
