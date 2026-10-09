//
//  AppleReauthorization.swift
//  the-human-internet
//

import AuthenticationServices
import UIKit

enum AppleReauthorizationError: Error {
    case missingAuthorizationCode
}

/// Asks the signed-in user to confirm with Sign in with Apple once more, and
/// returns the fresh authorization code Apple hands back.
///
/// Only used for account deletion: the backend's `delete-account` exchanges
/// that code for a token and revokes it, so the app stops being linked to
/// the user's Apple ID. It has to be fresh because nothing ever kept a token
/// from the original sign-in — `signInWithIdToken` uses the ID token alone —
/// and a code is single-use and expires in five minutes. Doubles as a
/// Face ID "are you sure" for something irreversible.
///
/// Not part of `AppleAuthService`, which is built around the SwiftUI
/// `SignInWithAppleButton`; this one has no button, so it drives an
/// `ASAuthorizationController` itself. A cancelled prompt throws
/// `ASAuthorizationError.canceled`.
@MainActor
final class AppleReauthorization: NSObject {
    private var continuation: CheckedContinuation<String, Error>?

    func requestAuthorizationCode() async throws -> String {
        // No scopes: name and email are only ever returned on the very first
        // authorization, and nothing here needs them anyway.
        let request = ASAuthorizationAppleIDProvider().createRequest()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }
}

extension AppleReauthorization: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?
            .authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }
        MainActor.assumeIsolated {
            if let code {
                continuation?.resume(returning: code)
            } else {
                continuation?.resume(throwing: AppleReauthorizationError.missingAuthorizationCode)
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

extension AppleReauthorization: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
