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
            DevMenuDescription(
                "Feature flags are shared: changing one changes the app for every user it applies to, not just for you."
            )

            Section {
                flagPicker("Show Stripe Identity Verification", key: FeatureFlagKey.stripeIdentityVerification)
                flagPicker("Custom Verification Pages", key: FeatureFlagKey.customVerificationPages)
                flagPicker("Require App Attest for Signing", key: FeatureFlagKey.requireAppAttest)
                flagPicker("Server-Side Watermark", key: FeatureFlagKey.serverSideWatermark)
            } footer: {
                Text("All: on for every user. Admin: on only for admin accounts — use it to try a change against real data before everyone gets it. Off: on for nobody.\n\nCustom Verification Pages is also read server-side, resolved against each photo's owner — turning it off retracts names and handles from pages already out there, not just the editor in Settings.\n\nRequire App Attest for Signing is read only by the server: while it's on for someone, a photo that can't prove it came from this app on a real iPhone isn't signed. The Simulator can't prove that, and neither can any build older than App Attest — don't set All until those are gone.\n\nServer-Side Watermark: the signing server burns the mark in and keeps the unwatermarked capture as the photo's C2PA ingredient. Only turn it on once the new signing Lambda and sign-photo are deployed — before that, uploads stall and retry.")
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
            selection: Binding(
                get: { appState.audience(for: key) },
                set: { setAudience(key, to: $0) }
            )
        ) {
            ForEach(FeatureFlagAudience.allCases) { audience in
                Text(audience.label).tag(audience)
            }
        } label: {
            // A `Text` label rather than the string initializer so the longer
            // flag names wrap instead of truncating to an ambiguous prefix.
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pickerStyle(.menu)
        .tint(Theme.accentBlue)
    }

    private func setAudience(_ key: String, to audience: FeatureFlagAudience) {
        Task {
            do {
                try await appState.setAudience(audience, for: key)
            } catch {
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
