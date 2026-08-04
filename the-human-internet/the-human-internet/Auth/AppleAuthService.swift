//
//  AppleAuthService.swift
//  the-human-internet
//

import Foundation
import AuthenticationServices
import CryptoKit
import Observation
import Supabase

enum AppleAuthError: Error {
    case invalidCredential
    case missingIdentityToken
}

@Observable
final class AppleAuthService {
    private(set) var isAuthenticating = false
    private var currentNonce: String?

    /// Called from `SignInWithAppleButton`'s `onRequest` — sets up the nonce and scopes.
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)
    }

    /// Called from `SignInWithAppleButton`'s `onCompletion`.
    func handle(_ result: Result<ASAuthorization, Error>) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }

        let authorization = try result.get()

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AppleAuthError.invalidCredential
        }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AppleAuthError.missingIdentityToken
        }

        let nonce = currentNonce
        currentNonce = nil

        // Requires the Apple provider to be configured in Supabase
        // (Authentication > Providers > Apple — needs a Services ID, Team ID, Key ID,
        // and private key from your Apple Developer account) or this throws an
        // "provider is not enabled" error from Supabase Auth.
        try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess)

            for random in randoms where remainingLength > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
