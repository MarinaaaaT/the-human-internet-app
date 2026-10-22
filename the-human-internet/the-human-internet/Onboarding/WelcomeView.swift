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
                // A brand moment: the wordmark alone, faded in by opacity
                // only (`BrandReveal`).
                BrandReveal {
                    Wordmark(height: DesignTokens.Space.s6)
                }
                Spacer()
                // Labelled for the first-timer, but it's the same call either
                // way: `signInWithIdToken` creates the account or signs into
                // an existing one, so a returning user is signed in by it too.
                SignInWithAppleButton(.signUp, onRequest: onConfigureRequest, onCompletion: onCompletion)
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
