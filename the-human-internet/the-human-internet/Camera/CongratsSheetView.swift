//
//  CongratsSheetView.swift
//  the-human-internet
//

import SwiftUI

struct CongratsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DesignTokens.Space.s6) {
            // The success state is a brand moment: the mark, revealed.
            BrandReveal {
                BrandMark(size: DesignTokens.Size.thumbnail)
            }
            Text("Congrats on your\nfirst verified photo!")
                .textStyle(DesignTokens.TextStyles.h2)
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
                bullet("All photos are saved to your camera roll. With or without your account, you'll still have them.")
                bullet("Every photo on our app carries proof — exactly what proof is up to you. Choose this in settings.")
            }

            PrimaryButton(title: "Got it") { dismiss() }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Space.s6)
        .padding(.top, DesignTokens.Space.s8)
        .fittedSheet()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Space.s2) {
            Text("•").foregroundStyle(Theme.mutedForeground)
            Text(text)
                .textStyle(DesignTokens.TextStyles.body)
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        CongratsSheetView()
    }
}
