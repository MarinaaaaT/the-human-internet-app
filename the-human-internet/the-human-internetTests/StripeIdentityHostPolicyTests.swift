//
//  StripeIdentityHostPolicyTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// Pins the origin allowlist guarding the Stripe Identity WKWebView.
///
/// This exists because the screen it protects is currently impossible to test
/// by hand: the `stripe_identity_verification` feature flag is off, and the
/// Stripe account's Identity product isn't activated, so no VerificationSession
/// URL can be minted to load. The policy is pure, though, so the interesting
/// half is testable regardless — and it fails in both directions. Too strict
/// and the flow dead-ends on a blank screen; too loose and an arbitrary origin
/// inherits camera access on a screen that photographs a government ID.
struct StripeIdentityHostPolicyTests {
    // MARK: - The return URL

    /// The half that actually broke: Stripe validates `return_url` and
    /// answers `url_invalid` for a custom scheme, so every session creation
    /// 400'd before this became an https URL. These pin it against the
    /// `RETURN_URL` constant in the stripe-identity-session Edge Function,
    /// which nothing else can check — a drift between them ends the flow on a
    /// screen that never dismisses.
    @Test("The https return_url is recognised")
    func recognisesTheReturnURL() {
        #expect(StripeIdentityHostPolicy.isReturnURL(URL(string: "https://the-human-internet.com/identity-verification-return")))
        #expect(StripeIdentityHostPolicy.isReturnURL(URL(string: "https://www.the-human-internet.com/identity-verification-return")))
        #expect(StripeIdentityHostPolicy.isReturnURL(URL(string: "https://the-human-internet.com/identity-verification-return/")))
        #expect(StripeIdentityHostPolicy.isReturnURL(URL(string: "https://the-human-internet.com/identity-verification-return?x=1")))
    }

    /// Sessions minted before the switch to https still complete.
    @Test("The legacy custom-scheme return is still recognised")
    func recognisesTheLegacyCustomScheme() {
        #expect(StripeIdentityHostPolicy.isReturnURL(URL(string: "thehumaninternet://identity-verification-return")))
    }

    /// Recognising the return URL cancels navigation and reports success, so
    /// anything that isn't it must not be mistaken for it — least of all a
    /// page on our own domain that merely starts with the same path.
    @Test("Other URLs are not the return URL", arguments: [
        "https://the-human-internet.com/",
        "https://the-human-internet.com/identity-verification-returned",
        "https://the-human-internet.com/identity-verification-return/extra",
        "https://evil.com/identity-verification-return",
        "https://the-human-internet.com.evil.com/identity-verification-return",
        "http://the-human-internet.com/identity-verification-return",
        "https://verify.stripe.com/start/test_abc123"
    ])
    func refusesEverythingElse(urlString: String) {
        #expect(!StripeIdentityHostPolicy.isReturnURL(URL(string: urlString)))
    }

    @Test("Stripe's hosted Identity host is allowed")
    func allowsTheHostedIdentityHost() {
        #expect(StripeIdentityHostPolicy.allows(host: "verify.stripe.com"))
        #expect(StripeIdentityHostPolicy.allowsNavigation(to: URL(string: "https://verify.stripe.com/start/test_abc123")))
    }

    @Test("Subdomains of the hosted Identity host are allowed")
    func allowsSubdomains() {
        #expect(StripeIdentityHostPolicy.allows(host: "eu.verify.stripe.com"))
        #expect(StripeIdentityHostPolicy.allows(host: "a.b.verify.stripe.com"))
    }

    /// The leading dot in the subdomain arm is the whole defence here — a bare
    /// `hasSuffix("verify.stripe.com")` accepts every one of these.
    @Test("Lookalike hosts that merely end in the allowed host are refused", arguments: [
        "notverify.stripe.com",
        "xverify.stripe.com",
        "evil-verify.stripe.com"
    ])
    func refusesSuffixLookalikes(host: String) {
        #expect(!StripeIdentityHostPolicy.allows(host: host))
    }

    /// A prefix match would accept these, and they are attacker-controlled.
    @Test("Hosts that merely contain the allowed host are refused", arguments: [
        "verify.stripe.com.evil.com",
        "verify.stripe.com.attacker.io"
    ])
    func refusesPrefixLookalikes(host: String) {
        #expect(!StripeIdentityHostPolicy.allows(host: host))
    }

    /// Other Stripe-owned hosts are refused on purpose: they're plausible
    /// (`js.stripe.com` and `m.stripe.network` serve the helper frames Stripe
    /// pages embed) but none of them should inherit camera access here. If the
    /// flow ever genuinely needs one, it gets added explicitly.
    @Test("Other Stripe-owned hosts are not implicitly trusted", arguments: [
        "stripe.com",
        "js.stripe.com",
        "api.stripe.com",
        "m.stripe.network",
        "checkout.stripe.com"
    ])
    func refusesOtherStripeHosts(host: String) {
        #expect(!StripeIdentityHostPolicy.allows(host: host))
    }

    @Test("A missing host is refused rather than treated as same-origin")
    func refusesNilHost() {
        #expect(!StripeIdentityHostPolicy.allows(host: nil))
        #expect(!StripeIdentityHostPolicy.allowsNavigation(to: nil))
        // `about:blank` and `data:` URLs have no host at all.
        #expect(!StripeIdentityHostPolicy.allowsNavigation(to: URL(string: "about:blank")))
    }

    /// Hostnames are case-insensitive but `URL.host` preserves the case the
    /// page wrote, so without normalising, a redirect to a shouted host would
    /// be blocked as if it were a foreign origin — a false positive that would
    /// present as an unexplained blank screen.
    @Test("Host matching ignores case")
    func matchesHostCaseInsensitively() {
        #expect(StripeIdentityHostPolicy.allows(host: "VERIFY.STRIPE.COM"))
        #expect(StripeIdentityHostPolicy.allows(host: "Verify.Stripe.Com"))
        #expect(StripeIdentityHostPolicy.allows(scheme: "HTTPS", host: "verify.stripe.com"))
    }

    /// The URL carries the VerificationSession's client secret and the payload
    /// carries a document scan, so the right host over plaintext is still no.
    @Test("Non-https schemes are refused even on the allowed host", arguments: [
        "http", "ftp", "file"
    ])
    func refusesNonHTTPSSchemes(scheme: String) {
        #expect(!StripeIdentityHostPolicy.allows(scheme: scheme, host: "verify.stripe.com"))
    }

    /// The custom scheme is how the flow signals completion. It's handled by an
    /// earlier branch in the navigation delegate, so the policy itself must
    /// still refuse it — if the ordering there ever changed, allowing it here
    /// would let the WKWebView try to navigate to it instead.
    @Test("The app's own return scheme is not itself an allowed navigation")
    func refusesTheReturnScheme() {
        #expect(!StripeIdentityHostPolicy.allowsNavigation(
            to: URL(string: "thehumaninternet://identity-verification-return")
        ))
    }
}
