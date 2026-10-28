//
//  DemoAccount.swift
//  the-human-internet
//

import Foundation
import Supabase

/// The shared demo account, opened by `thehumaninternet://demo` instead of
/// Sign in with Apple.
///
/// Everything that makes it a demo is decided server-side, never here:
/// - `demo-session` (backend) creates the account on first use, **resets
///   everything about it except its photos** on every call — the username
///   back to "demo account", onboarding back to the profile step,
///   verification back to `unverified` — and hands back a session.
/// - `stripe-identity-session` approves it without ever reaching Stripe.
/// - `users.is_demo` marks it, and only the service role can write it, so
///   the verification pages can trust it to say "human authenticity is not
///   guaranteed".
///
/// The one thing the app does differently for it is burn "DEMO" into each
/// photo along with the fingerprint — see `PhotoUploadQueue` and
/// `DemoWatermark`.
enum DemoAccount {
    /// The `demo` in `thehumaninternet://demo`.
    static let deepLinkHost = "demo"

    /// Shown in place of "This photo was taken by a real human!" on the
    /// in-app verification page. The website's `/[photoId]` page says the
    /// same thing.
    static let verificationDisclaimer = "This photo was taken on a demo account so human authenticity is not guaranteed."

    static func isEntryLink(_ url: URL) -> Bool {
        url.scheme == VerifiedPhoto.deepLinkScheme && url.host == deepLinkHost
    }

    /// Resets the demo account and returns a session for it.
    static func startSession() async throws -> (accessToken: String, refreshToken: String) {
        struct Response: Decodable {
            let accessToken: String
            let refreshToken: String
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
            }
        }
        let response: Response = try await supabase.functions.invoke("demo-session")
        return (response.accessToken, response.refreshToken)
    }
}
