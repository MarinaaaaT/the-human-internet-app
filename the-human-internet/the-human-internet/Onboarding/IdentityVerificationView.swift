//
//  IdentityVerificationView.swift
//  the-human-internet
//

import SwiftUI

struct IdentityVerificationView: View {
    @Environment(AppState.self) private var appState
    var onFinish: () -> Void

    @State private var phoneNumber = ""
    // SSN last-four — validated locally only, never written to `appState.user` or
    // upserted anywhere. `HumanUser`/the `users` table have no field for it by design.
    @State private var digits = ["", "", "", ""]
    @FocusState private var focusedDigit: Int?

    private var isValid: Bool {
        !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty && digits.allSatisfy { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Verify your identity")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("The information is only used to verify your identity. It will not be publicly visible and remains completely private.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Phone Number")
                    HITextField(placeholder: "Phone Number", text: $phoneNumber, keyboardType: .phonePad)
                }

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Last 4 Digits of Social Security")
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { index in
                            DigitBox(text: $digits[index], focusBinding: $focusedDigit, index: index, count: 4)
                        }
                    }
                }

                Spacer()

                PrimaryButton(title: "Finish", isEnabled: isValid) {
                    appState.user.phoneNumber = phoneNumber
                    onFinish()
                }
            }
            .padding(24)
            .padding(.top, 24)
        }
        .onAppear {
            // Resuming after a previous session — prefill what was already entered.
            // SSN digits are intentionally excluded: never stored, so never prefilled.
            phoneNumber = appState.user.phoneNumber
        }
    }
}

#Preview {
    NavigationStack {
        IdentityVerificationView(onFinish: {})
            .environment(AppState())
    }
}
