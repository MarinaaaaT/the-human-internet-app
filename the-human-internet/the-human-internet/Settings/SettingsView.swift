//
//  SettingsView.swift
//  the-human-internet
//

import SwiftUI

/// The pages Settings pushes. A value rather than a flag per page so one
/// page can link to another — Photo settings' social-media row opens
/// Profile settings, where the handles are edited.
enum SettingsPage: Hashable {
    case profile
    case photo
    case account
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var showFeedback = false
    @State private var showSignOutConfirmation = false
    @State private var signOutErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    pageRow(.profile, title: "Profile settings", value: "Profile information")
                    Divider().overlay(Theme.border)
                    pageRow(.photo, title: "Photo settings", value: "Photo capture, data, and sharing")
                    Divider().overlay(Theme.border)
                    pageRow(.account, title: "Account settings", value: "General settings and account deletion")
                    Divider().overlay(Theme.border)

                    // Leaves the app on purpose: a Discord invite needs the
                    // user's own logged-in Discord session, so it belongs in
                    // the Discord app (or Safari), not a WKWebView.
                    SettingsRow(title: "Contact us", value: "Join our Discord", systemImage: "arrow.up.right") {
                        UIApplication.shared.open(ExternalLink.discord)
                    }
                    Divider().overlay(Theme.border)

                    SettingsRow(title: "Feedback", value: "Share an idea or issue", systemImage: "arrow.up.right") {
                        showFeedback = true
                    }
                    Divider().overlay(Theme.border)

                    SettingsRow(title: "Log out", systemImage: "rectangle.portrait.and.arrow.right") {
                        showSignOutConfirmation = true
                    }

                    Spacer()
                }
                .padding(.top, DesignTokens.Space.s2)
            }
            .settingsTitle("Settings")
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .profile:
                    ProfileSettingsView()
                case .photo:
                    PhotoSettingsView()
                case .account:
                    AccountSettingsView(onAccountDeleted: { dismiss() })
                }
            }
        }
        // Settings is where verification status is actually read, so it
        // refreshes on open — and then keeps watching, but only while the
        // status is one that resolves on its own. `in_progress` is waiting on
        // stripe-identity-webhook, which can land at any moment; every other
        // status is at rest and polling it would be pointless. The loop is
        // bound to the view: `.task` cancels it when Settings closes. It sits
        // outside the stack, so it keeps running while a page is pushed —
        // Profile settings is where the status is shown.
        .task {
            await appState.refreshVerificationStatus()
            while !Task.isCancelled, appState.user.verificationStatus == .inProgress {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await appState.refreshVerificationStatus()
            }
        }
        // In-app rather than a browser hand-off: the board is read-and-post,
        // so keeping it in a sheet means the user comes straight back to
        // whatever they were doing.
        .sheet(isPresented: $showFeedback) {
            WebPreviewView(url: ExternalLink.feedback)
        }
        .confirmationDialog("Log out of the human internet?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Couldn't log out",
            isPresented: Binding(get: { signOutErrorMessage != nil }, set: { if !$0 { signOutErrorMessage = nil } })
        ) {
            Button("OK") { signOutErrorMessage = nil }
        } message: {
            Text(signOutErrorMessage ?? "Please try again.")
        }
    }

    private func pageRow(_ page: SettingsPage, title: String, value: String) -> some View {
        NavigationLink(value: page) {
            SettingsRowLabel(title: title, value: value, systemImage: "chevron.right")
        }
        .buttonStyle(.plain)
    }

    private func signOut() {
        Task {
            do {
                try await appState.signOut()
                dismiss()
            } catch {
                signOutErrorMessage = "Please try again."
                Log.auth.error("Sign-out failed: \(error, privacy: .public)")
            }
        }
    }
}

extension View {
    /// The bar draws `navigationTitle` in the system font whatever the
    /// environment says; this puts the visible title in ours. Every Settings
    /// page uses it, so they all title themselves the same way.
    func settingsTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .textStyle(DesignTokens.TextStyles.title)
                        .foregroundStyle(Theme.foreground)
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }
}

/// The off-app destinations Settings links out to.
private enum ExternalLink {
    static let discord = URL(string: "https://discord.com/invite/SjYNad553")!
    static let feedback = URL(string: "https://thehumaninternet.featurebase.app/")!
}

#Preview {
    SettingsView()
        .environment(AppState())
}
