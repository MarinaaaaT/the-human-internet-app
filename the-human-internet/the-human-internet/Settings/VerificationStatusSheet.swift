//
//  VerificationStatusSheet.swift
//  the-human-internet
//

import SwiftUI

/// Explains what the user's current verification status means. A dumb view —
/// it takes the status rather than reading AppState, matching the rest of the
/// Settings sheets.
struct VerificationStatusSheet: View {
    let status: VerificationStatus

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                SheetGrabber()

                Text("Verification Status")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()
            }
            .padding(24)
            .padding(.top, 16)
        }
        .presentationDetents([.fraction(0.4)])
        .presentationBackground(Theme.background)
    }

    private var paragraphs: [String] {
        switch status {
        case .unverified:
            return [
                "Identity verification is 100% optional. You can capture and share verified photos without it.",
                "If you would ever like to use the human internet to make claims about the ownership of your content, you will need to verify your identity. You can start that any time from Settings.",
            ]
        case .inProgress:
            return [
                "Your identity verification has been submitted and is being reviewed.",
                "While it is in progress, content you share will clearly state that you are an unverified human.",
            ]
        case .verified:
            return [
                "Your identity is verified. Content you share is attributed to you as a verified human.",
            ]
        case .failed:
            return [
                "Your identity verification didn't go through.",
                "You can keep using the human internet — verification is optional — but you'll need a successful verification to make claims about the ownership of your content.",
            ]
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        VerificationStatusSheet(status: .unverified)
    }
}
