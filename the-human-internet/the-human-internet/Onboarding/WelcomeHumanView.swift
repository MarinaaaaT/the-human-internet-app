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
                Image("DoodleHand")
                    .resizable()
                    .scaledToFit()
                    .frame(width: DesignTokens.Space.s24, height: DesignTokens.Space.s24)
                    .accessibilityHidden(true)
                Text("Welcome human.")
                    .textStyle(DesignTokens.TextStyles.h2)
                    .foregroundStyle(Theme.foreground)
                Text("You're verified. From here on, every photo you take can carry proof that a real person took it — not a bot, not a model. Let's take your first one.")
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
