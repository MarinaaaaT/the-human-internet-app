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
                BrandMark(size: 56)
                    .padding(.bottom, 24)
                Text("Welcome to\nthe human internet")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Spacer()
                SignInWithAppleButton(.signIn, onRequest: onConfigureRequest, onCompletion: onCompletion)
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .disabled(isBusy)
                    .opacity(isBusy ? 0.5 : 1)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    WelcomeView(onConfigureRequest: { _ in }, onCompletion: { _ in })
}
