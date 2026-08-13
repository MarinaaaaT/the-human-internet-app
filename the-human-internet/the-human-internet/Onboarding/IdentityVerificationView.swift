//
//  IdentityVerificationView.swift
//  the-human-internet
//

import SwiftUI

struct IdentityVerificationView: View {
    @Environment(AppState.self) private var appState
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
                    Text("Verify your identity")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("You'll scan a government-issued ID and take a quick selfie. It will not be publicly visible and remains completely private.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Phone Number")
                    HITextField(placeholder: "Phone Number", text: $phoneNumber, keyboardType: .phonePad)
                }

                Spacer()

                PrimaryButton(
                    title: isCreatingSession ? "Starting verification…" : "Verify with ID",
                    isEnabled: isValid && !isCreatingSession
                ) {
                    appState.user.phoneNumber = phoneNumber
                    startVerification()
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
                StripeIdentityWebView(url: verificationURL, onComplete: onFinish)
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
                debugPrint(error)
            }
            isCreatingSession = false
        }
    }
}

#Preview {
    NavigationStack {
        IdentityVerificationView(onFinish: {})
            .environment(AppState())
    }
}
