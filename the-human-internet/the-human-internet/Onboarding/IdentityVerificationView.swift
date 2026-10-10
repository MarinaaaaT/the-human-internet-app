//
//  IdentityVerificationView.swift
//  the-human-internet
//

import SwiftUI

/// The gate in front of Stripe's hosted flow: explains that verification is
/// optional and offers a way past it. Used both as onboarding's `.verify` step
/// and, for someone who skipped, from Settings — hence `skipTitle`, the only
/// thing that differs between the two contexts.
struct IdentityVerificationView: View {
    @Environment(AppState.self) private var appState
    /// "Skip" mid-onboarding, "Not now" when this is reachable again later.
    var skipTitle: String = "Skip"
    var onSkip: () -> Void
    /// Called once Stripe redirects back, meaning the user submitted. The
    /// verified/failed outcome lands later, via the webhook.
    var onFinish: () -> Void

    @State private var isCreatingSession = false
    @State private var verificationURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DesignTokens.Space.s8) {
                VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
                    Text("Verify your identity (optional)")
                        .textStyle(DesignTokens.TextStyles.h2)
                        .foregroundStyle(Theme.foreground)
                    Text("Identity verification on our site is 100% optional. However, if you would ever like to use our site to make claims about the ownership of your content, you will need to verify your identity.")
                        .textStyle(DesignTokens.TextStyles.body)
                        .foregroundStyle(Theme.mutedForeground)
                    Text("If you do verify, you'll scan a government-issued ID and take a quick selfie. It will not be publicly visible and remains completely private.")
                        .textStyle(DesignTokens.TextStyles.body)
                        .foregroundStyle(Theme.mutedForeground)

                    // Admin-only, and never reachable by a real user — see
                    // `AppState.isStripeIdentityTestModeEnabled`. Without it
                    // the two environments are indistinguishable from inside
                    // the app, which is the one thing that makes testing
                    // against both of them error-prone.
                    if appState.isStripeIdentityTestModeEnabled {
                        Text("Stripe test environment — this verification is a sandbox one and proves nothing about a real identity.")
                            .textStyle(DesignTokens.TextStyles.caption)
                            .foregroundStyle(Theme.foreground)
                    }
                }

                Spacer()

                VStack(spacing: DesignTokens.Space.s2) {
                    PrimaryButton(
                        title: isCreatingSession ? "Starting verification…" : "Verify identity",
                        isEnabled: !isCreatingSession
                    ) {
                        startVerification()
                    }

                    TertiaryButton(title: skipTitle) {
                        // Leaves verificationStatus at .unverified — skipping is
                        // a resting state, not a pending one.
                        onSkip()
                    }
                    .disabled(isCreatingSession)
                }
            }
            .padding(DesignTokens.Space.s6)
            .padding(.top, DesignTokens.Space.s6)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { verificationURL != nil },
                set: { if !$0 { verificationURL = nil } }
            )
        ) {
            if let verificationURL {
                StripeIdentityWebView(url: verificationURL) {
                    // Submitted — now genuinely pending until the
                    // stripe-identity-webhook Edge Function resolves it. The
                    // caller is responsible for persisting this.
                    //
                    // `unverified -> in_progress` is the *only* change to this
                    // column a client is allowed to make: the
                    // prevent_self_verification_escalation trigger reverts
                    // every other transition, silently and without an error, so
                    // that nobody can PATCH their own row to `verified`. Any
                    // new transition has to go through a service_role path
                    // (i.e. the webhook), not through this upsert.
                    appState.user.verificationStatus = .inProgress
                    onFinish()
                }
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

    private func startVerification() {
        isCreatingSession = true
        Task {
            do {
                verificationURL = try await UserProfileRepository.createIdentityVerificationSession()
            } catch {
                errorMessage = "Couldn't start verification — please try again."
                Log.onboarding.error("Creating identity verification session failed: \(error, privacy: .public)")
            }
            isCreatingSession = false
        }
    }
}

#Preview {
    NavigationStack {
        IdentityVerificationView(onSkip: {}, onFinish: {})
            .environment(AppState())
    }
}
