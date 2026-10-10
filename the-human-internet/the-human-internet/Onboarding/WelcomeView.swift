//
//  WelcomeView.swift
//  the-human-internet
//

import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    var isBusy: Bool = false
    var onConfigureRequest: (ASAuthorizationAppleIDRequest) -> Void
    var onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack {
                Spacer()
                // A brand moment: the mark, then the words, faded in by
                // opacity only (`BrandReveal`).
                BrandReveal(index: 0) {
                    BrandMark(size: DesignTokens.Size.thumbnail)
                        .padding(.bottom, DesignTokens.Space.s6)
                }
                BrandReveal(index: 1) {
                    VStack(spacing: DesignTokens.Space.s3) {
                        Text("Welcome to")
                            .textStyle(DesignTokens.TextStyles.h2)
                            .foregroundStyle(Theme.foreground)
                        Wordmark(height: DesignTokens.Space.s6)
                    }
                }
                Spacer()
                SignInWithAppleButton(.signIn, onRequest: onConfigureRequest, onCompletion: onCompletion)
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: DesignTokens.Size.controlHeight)
                    .clipShape(Capsule())
                    .disabled(isBusy)
                    .opacity(isBusy ? 0.5 : 1)
                    .padding(.horizontal, DesignTokens.Space.s8)
                    .padding(.bottom, DesignTokens.Space.s12)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    WelcomeView(onConfigureRequest: { _ in }, onCompletion: { _ in })
}
