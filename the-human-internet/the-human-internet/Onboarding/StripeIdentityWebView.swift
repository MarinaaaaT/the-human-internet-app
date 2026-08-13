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

private struct IdentityWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    let onReturnURL: () -> Void

    /// Matches the scheme registered for `thehumaninternet://...` deep links.
    private static let returnScheme = "thehumaninternet"

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

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
            if navigationAction.request.url?.scheme == IdentityWebView.returnScheme {
                decisionHandler(.cancel)
                onReturnURL()
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
        // tab and covers this prompt too.
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }
    }
}

#Preview {
    StripeIdentityWebView(url: URL(string: "https://verify.stripe.com")!, onComplete: {})
}
