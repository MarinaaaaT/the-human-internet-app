//
//  WebPreviewView.swift
//  the-human-internet
//

import SwiftUI
import WebKit

/// A plain in-app web sheet: close button, host label, the page. Two callers.
///
/// The "unknown internet lurker" half of Preview — the real, live
/// `the-human-internet.com/{id}` page, exactly as it renders for a
/// signed-out web visitor. The website (a separate repo) already does the
/// Public/Humans Only privacy split server-side, so there's no client-side
/// privacy logic here.
///
/// And Settings' Feedback row, which loads the public Featurebase board.
struct WebPreviewView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .symbolStyle(DesignTokens.TextStyles.title)
                            .ctaIcon()
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                    Text(url.host ?? "")
                        .textStyle(DesignTokens.TextStyles.caption)
                        .foregroundStyle(Theme.mutedForeground)
                    Spacer()
                    // Balances the close button so the host label stays centered.
                    Color.clear.frame(width: DesignTokens.Size.iconButton, height: DesignTokens.Size.iconButton)
                }
                .padding(.horizontal, DesignTokens.Space.s6)
                .padding(.top, DesignTokens.Space.s3)
                .padding(.bottom, DesignTokens.Space.s2)

                ZStack {
                    WebView(url: url, isLoading: $isLoading)
                    if isLoading {
                        ProgressView().tint(Theme.foreground)
                    }
                }
            }
        }
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        /// `target="_blank"` links — which the feedback board uses — are
        /// dropped on the floor by default, since WKWebView has nowhere to
        /// put a second window. Load them in place instead, so a tap does
        /// something rather than nothing.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
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
    }
}

#Preview {
    WebPreviewView(url: URL(string: "https://the-human-internet.com")!)
}
