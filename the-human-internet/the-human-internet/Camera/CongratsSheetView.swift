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
                // Not a Spacer: one sharing this VStack offered the bullets
                // only part of the spare height, so each was cut to two lines
                // with room left over. A scroll view gives the copy all the
                // height it asks for, and only scrolls if a large text size
                // genuinely outgrows the sheet.
                ScrollView {
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
                            bullet("All photos are saved to your camera roll. With or without your account, you'll still have them.")
                            bullet("Every photo on our app carries proof — exactly what proof is up to you. Choose this in settings.")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)

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
