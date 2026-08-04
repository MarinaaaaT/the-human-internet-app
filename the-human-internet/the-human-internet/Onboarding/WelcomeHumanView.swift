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
            VStack(spacing: 20) {
                Spacer()
                Text("👋")
                    .font(.system(size: 64))
                Text("Welcome human.")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                Text("You're verified. From here on, every photo you take can carry proof that a real person took it — not a bot, not a model. Let's take your first one.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                PrimaryButton(title: "Take your first photo", action: onTakePhoto)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    WelcomeHumanView(onTakePhoto: {})
}
