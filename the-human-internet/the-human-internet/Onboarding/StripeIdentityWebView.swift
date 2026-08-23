//
//  StripeIdentityWebView.swift
//  the-human-internet
//

import SwiftUI
import WebKit

/// Presents Stripe's hosted Identity verification flow (document scan +
/// selfie match) in a modal WKWebView. A dedicated wrapper rather than a
/// reuse of Sharing/WebPreviewView.swift — that one serves an unrelated
/// purpose (previewing the signed-out web page) and isn't suited to
/// intercepting a return-URL redirect or granting camera access.
struct StripeIdentityWebView: View {
    let url: URL
    /// Called when Stripe redirects back to `thehumaninternet://identity-verification-return`,
    /// meaning the user finished submitting (not necessarily verified yet —
    /// that result arrives later via the stripe-identity-webhook Edge Function).
    var onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button {
                        // Cancelled, not completed — just dismiss. The onboarding
                        // step stays put so the user can retry.
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text("Verify with ID")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Color.clear.frame(width: 18, height: 18)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ZStack {
                    IdentityWebView(url: url, isLoading: $isLoading) {
                        dismiss()
                        onComplete()
                    }
                    if isLoading {
                        ProgressView().tint(.white)
                    }
                }
            }
        }
    }
}

/// Which origins this screen will navigate to, or hand the camera to.
///
/// This screen captures a government ID and a selfie, so both are restricted
/// to Stripe's own hosted Identity origin — a redirect, an embedded
/// third-party frame, or a future change on Stripe's side must not be able to
/// silently pick up camera/mic access or steer this view. Stripe's hosted
/// Identity flow is served from `verify.stripe.com`; if a legitimate flow
/// needs another host, add it here explicitly rather than opening this up.
///
/// Deliberately split out of the delegate that uses it so the allowlist is
/// unit-testable without a live Stripe session. That matters more here than
/// it normally would: the Stripe account's Identity product isn't activated
/// yet and the `stripe_identity_verification` flag is off, so this policy
/// cannot currently be exercised by hand at all — `StripeIdentityHostPolicyTests`
/// is the only thing between a typo here and a screen that silently refuses
/// to load.
enum StripeIdentityHostPolicy {
    private static let allowedHost = "verify.stripe.com"

    /// A `nil` host, or any host outside Stripe's Identity domain, is refused.
    /// The subdomain arm keeps the leading dot on purpose: a bare
    /// `hasSuffix("verify.stripe.com")` would also accept a lookalike like
    /// `notverify.stripe.com`. Hosts are compared lowercased because `URL.host`
    /// preserves whatever case the page wrote, while hostnames are
    /// case-insensitive — without this, a redirect to `VERIFY.STRIPE.COM`
    /// would be blocked as if it were a foreign origin.
    static func allows(host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == allowedHost || host.hasSuffix(".\(allowedHost)")
    }

    /// Navigations and camera grants must additionally be `https`: the flow
    /// carries a session secret in the URL and a document scan in the payload,
    /// so a plaintext origin is not an acceptable stand-in even on an
    /// otherwise-allowed host.
    static func allows(scheme: String?, host: String?) -> Bool {
        scheme?.lowercased() == "https" && allows(host: host)
    }

    static func allowsNavigation(to url: URL?) -> Bool {
        allows(scheme: url?.scheme, host: url?.host)
    }
}

private struct IdentityWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    let onReturnURL: () -> Void

    /// Matches the scheme registered for `thehumaninternet://...` deep links.
    private static let returnScheme = "thehumaninternet"

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // Leaves nothing on disk once the sheet is dismissed — this session
        // handles ID documents and selfies.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, onReturnURL: onReturnURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding var isLoading: Bool
        let onReturnURL: () -> Void

        init(isLoading: Binding<Bool>, onReturnURL: @escaping () -> Void) {
            _isLoading = isLoading
            self.onReturnURL = onReturnURL
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let requestURL = navigationAction.request.url
            if requestURL?.scheme == IdentityWebView.returnScheme {
                decisionHandler(.cancel)
                onReturnURL()
                return
            }
            guard StripeIdentityHostPolicy.allowsNavigation(to: requestURL) else {
                // Cancelling renders as a screen that just stops, with nothing
                // to distinguish "Stripe is slow" from "the allowlist refused a
                // step Stripe actually needs". Since this path can't be
                // exercised by hand until Identity is activated, the log is the
                // only evidence a future debugger will have. The frame kind is
                // the useful part: an embedded subframe is the likeliest false
                // positive, because Stripe's hosted pages carry cross-origin
                // helper frames that are not on `verify.stripe.com`.
                //
                // Origin only, never the full URL — a hosted Identity link
                // carries the VerificationSession's client secret in its path.
                Log.onboarding.error("""
                    Stripe Identity: blocked \(Self.frameKind(of: navigationAction), privacy: .public) \
                    navigation to \(Self.origin(of: requestURL), privacy: .public)
                    """)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        // Document + selfie capture inside the hosted Stripe page needs camera
        // access; NSCameraUsageDescription is already declared for the camera
        // tab and covers this prompt too. Only Stripe's own origin gets it.
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            guard StripeIdentityHostPolicy.allows(scheme: origin.protocol, host: origin.host) else {
                Log.onboarding.error("""
                    Stripe Identity: denied camera/mic to \(origin.protocol, privacy: .public)://\(origin.host, privacy: .public)
                    """)
                decisionHandler(.deny)
                return
            }
            decisionHandler(.grant)
        }

        /// Both helpers exist to keep secrets out of the log above.
        private static func origin(of url: URL?) -> String {
            "\(url?.scheme ?? "-")://\(url?.host ?? "-")"
        }

        private static func frameKind(of navigationAction: WKNavigationAction) -> String {
            guard let targetFrame = navigationAction.targetFrame else { return "new-window" }
            return targetFrame.isMainFrame ? "main-frame" : "subframe"
        }
    }
}

#Preview {
    StripeIdentityWebView(url: URL(string: "https://verify.stripe.com")!, onComplete: {})
}
