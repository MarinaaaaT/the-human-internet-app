//
//  CongratsSheetView.swift
//  the-human-internet
//

import SwiftUI

struct CongratsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("🎉")
                    .font(.system(size: 44))
                Text("Congrats on your\nfirst verified photo!")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    bullet("Your photos are currently public, which means anyone with the link can see them — including the robots. You can change this to humans only in your profile, so only people signed up to the human internet can verify photo contents.")
                    bullet("All photos are also saved to your camera roll, so if you ever lose access to your account, you keep your photos.")
                }

                Spacer()
                PrimaryButton(title: "Got it") { dismiss() }
            }
            .padding(24)
            .padding(.top, 32)
        }
        .presentationDetents([.fraction(0.65)])
        .presentationBackground(Theme.background)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(Theme.textSecondary)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        CongratsSheetView()
    }
}
