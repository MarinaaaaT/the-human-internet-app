//
//  WelcomeHumanView.swift
//  the-human-internet
//

import SwiftUI

struct WelcomeHumanView: View {
    var onTakePhoto: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: DesignTokens.Space.s6) {
                Spacer()
                BrandMark(size: DesignTokens.Size.thumbnail)
                Text("Welcome human.")
                    .textStyle(DesignTokens.TextStyles.h2)
                    .foregroundStyle(Theme.foreground)
                Text("Looks like you're real. From here on out, every photo you take will carry proof that a real person took it — not a bot, not AI. Let's take your first one.")
                    .textStyle(DesignTokens.TextStyles.body)
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.Space.s8)
                Spacer()
                PrimaryButton(title: "Take your first photo", action: onTakePhoto)
                    .padding(.horizontal, DesignTokens.Space.s8)
                    .padding(.bottom, DesignTokens.Space.s12)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    WelcomeHumanView(onTakePhoto: {})
}
