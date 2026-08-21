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

    @State private var phoneNumber = ""
    @State private var isCreatingSession = false
    @State private var verificationURL: URL?
    @State private var errorMessage: String?

    private var isValid: Bool {
        !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Verify your identity (optional)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Identity verification on our site is 100% optional. However, if you would ever like to use our site to make claims about the ownership of your content, you will need to verify your identity.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                    Text("If you do verify, you'll scan a government-issued ID and take a quick selfie. It will not be publicly visible and remains completely private.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Phone Number")
                    HITextField(placeholder: "Phone Number", text: $phoneNumber, keyboardType: .phonePad)
                }

                Spacer()

                VStack(spacing: 12) {
                    PrimaryButton(
                        title: isCreatingSession ? "Starting verification…" : "Verify Identity",
                        isEnabled: isValid && !isCreatingSession
                    ) {
                        appState.user.phoneNumber = phoneNumber
                        startVerification()
                    }

                    SecondaryButton(title: skipTitle) {
                        // Leaves verificationStatus at .unverified — skipping is
                        // a resting state, not a pending one.
                        onSkip()
                    }
                    .disabled(isCreatingSession)
                }
            }
            .padding(24)
            .padding(.top, 24)
        }
        .onAppear {
            // Resuming after a previous session — prefill what was already entered.
            phoneNumber = appState.user.phoneNumber
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
