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
            VStack(spacing: DesignTokens.Space.s6) {
                // The success state is a brand moment: the mark, revealed.
                BrandReveal {
                    BrandMark(size: DesignTokens.Size.thumbnail)
                }
                Text("Congrats on your\nfirst verified photo!")
                    .textStyle(DesignTokens.TextStyles.h2)
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
                    bullet("Your photos are currently public, which means anyone with the link can see them — including the robots. You can change this to humans only in your profile, so only people signed up to the human internet can verify photo contents.")
                    bullet("All photos are also saved to your camera roll, so if you ever lose access to your account, you keep your photos.")
                }

                Spacer()
                PrimaryButton(title: "Got it") { dismiss() }
            }
            .padding(DesignTokens.Space.s6)
            .padding(.top, DesignTokens.Space.s8)
        }
        .presentationDetents([.fraction(0.65)])
        .presentationBackground(Theme.background)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Space.s2) {
            Text("•").foregroundStyle(Theme.mutedForeground)
            Text(text)
                .textStyle(DesignTokens.TextStyles.body)
                .foregroundStyle(Theme.mutedForeground)
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        CongratsSheetView()
    }
}
