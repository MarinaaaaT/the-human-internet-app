//
//  SettingsView.swift
//  the-human-internet
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var showPrivacySheet = false
    @State private var showVerificationInfo = false
    @State private var showIdentityVerification = false
    @State private var showEditUsername = false
    @State private var showVerificationPage = false
    @State private var showFeedback = false
    @State private var showAccountSettings = false
    @State private var showSignOutConfirmation = false
    @State private var signOutErrorMessage: String?
    @State private var saveErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    settingsRow(title: "Username", value: appState.user.username.isEmpty ? "—" : appState.user.username, icon: "pencil") {
                        showEditUsername = true
                    }
                    Divider().overlay(Theme.border)
                    settingsRow(title: "Privacy", value: appState.user.privacy.rawValue, icon: "pencil") {
                        showPrivacySheet = true
                    }
                    Divider().overlay(Theme.border)
                    settingsRow(title: "Verification status", value: statusLabel, icon: "info.circle") {
                        showVerificationInfo = true
                    }
                    Divider().overlay(Theme.border)

                    // The reward for being verified: deciding what else goes
                    // on your public verification page beyond the photo —
                    // your real name, your social handles.
                    //
                    // Gated twice, and neither gate is the one that binds.
                    // `get_verification_photo()` re-checks *both* server-side
                    // — `verification_status`, and the same
                    // `custom_verification_pages` flag resolved against the
                    // photo's owner — before it hands any of these fields to
                    // the website. So this row appearing (or not) can't be
                    // what decides whether an unverified account publishes a
                    // name, and switching the flag off retracts what's
                    // already saved rather than just hiding the way to edit
                    // it.
                    if appState.isCustomVerificationPagesEnabled,
                       appState.user.verificationStatus == .verified {
                        settingsRow(
                            title: "Verification page",
                            value: "Customize",
                            icon: "chevron.right"
                        ) {
                            showVerificationPage = true
                        }
                        Divider().overlay(Theme.border)
                    }

                    // Verification is optional and skippable during onboarding,
                    // so this is the way back to it — gated twice, for two
                    // unrelated reasons:
                    //
                    // - The flag is a kill switch, and it has to close every
                    //   door at once. With "Show Stripe Identity Verification"
                    //   off, onboarding doesn't offer the step, so Settings
                    //   must not quietly remain a way in. Only the *action*
                    //   goes: the Verification Status row above still reports
                    //   whatever status the user already has, which stays true
                    //   and useful regardless of whether they can act on it.
                    // - Only offered to someone who hasn't started — an
                    //   in-progress user is waiting on the webhook, and
                    //   restarting would just orphan their session.
                    if appState.isStripeIdentityVerificationEnabled,
                       appState.user.verificationStatus == .unverified {
                        settingsRow(
                            title: "Identity verification",
                            value: "Verify identity",
                            icon: "chevron.right"
                        ) {
                            showIdentityVerification = true
                        }
                        Divider().overlay(Theme.border)
                    }

                    // Leaves the app on purpose: a Discord invite needs the
                    // user's own logged-in Discord session, so it belongs in
                    // the Discord app (or Safari), not a WKWebView.
                    settingsRow(
                        title: "Contact us",
                        value: "Join our Discord",
                        icon: "arrow.up.right"
                    ) {
                        UIApplication.shared.open(ExternalLink.discord)
                    }
                    Divider().overlay(Theme.border)

                    settingsRow(
                        title: "Feedback",
                        value: "Share an idea or issue",
                        icon: "chevron.right"
                    ) {
                        showFeedback = true
                    }
                    Divider().overlay(Theme.border)

                    settingsRow(
                        title: "Account settings",
                        value: "Manage your account",
                        icon: "chevron.right"
                    ) {
                        showAccountSettings = true
                    }
                    Divider().overlay(Theme.border)

                    Button {
                        showSignOutConfirmation = true
                    } label: {
                        HStack {
                            Text("Log out")
                                .textStyle(DesignTokens.TextStyles.body)
                            Spacer()
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .symbolStyle(DesignTokens.TextStyles.body)
                        }
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, DesignTokens.Space.s6)
                        .padding(.vertical, DesignTokens.Space.s4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.top, DesignTokens.Space.s2)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            // The bar draws `navigationTitle` in the system font whatever the
            // environment says; this puts the visible title in ours.
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .textStyle(DesignTokens.TextStyles.title)
                        .foregroundStyle(Theme.foreground)
                }
            }
            .navigationDestination(isPresented: $showAccountSettings) {
                AccountSettingsView(onAccountDeleted: { dismiss() })
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        // Settings is where verification status is actually read, so it
        // refreshes on open — and then keeps watching, but only while the
        // status is one that resolves on its own. `in_progress` is waiting on
        // stripe-identity-webhook, which can land at any moment; every other
        // status is at rest and polling it would be pointless. The loop is
        // bound to the view: `.task` cancels it when Settings closes.
        .task {
            await appState.refreshVerificationStatus()
            while !Task.isCancelled, appState.user.verificationStatus == .inProgress {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await appState.refreshVerificationStatus()
            }
        }
        .sheet(isPresented: $showPrivacySheet) {
            PrivacyEditSheet()
        }
        .sheet(isPresented: $showVerificationInfo) {
            VerificationStatusSheet(status: appState.user.verificationStatus)
        }
        .sheet(isPresented: $showEditUsername) {
            EditUsernameSheet()
        }
        .sheet(isPresented: $showVerificationPage) {
            VerificationPageSheet()
        }
        // In-app rather than a browser hand-off: the board is read-and-post,
        // so keeping it in a sheet means the user comes straight back to
        // whatever they were doing.
        .sheet(isPresented: $showFeedback) {
            WebPreviewView(url: ExternalLink.feedback)
        }
        .sheet(isPresented: $showIdentityVerification) {
            // "Not now" rather than "Skip": there's no flow to skip past here,
            // the sheet just closes and the row stays available.
            IdentityVerificationView(
                skipTitle: "Not now",
                onSkip: { showIdentityVerification = false },
                onFinish: {
                    showIdentityVerification = false
                    // Unlike onboarding, nothing else upserts afterwards — the
                    // phone number and the now-.inProgress status have to be
                    // persisted here or they're lost on relaunch.
                    saveProfile()
                }
            )
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
        .alert(
            "Couldn't save",
            isPresented: Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })
        ) {
            Button("OK") { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "Please try again.")
        }
    }

    private func saveProfile() {
        Task {
            do {
                try await UserProfileRepository.upsert(appState.user)
            } catch {
                saveErrorMessage = "Your verification was submitted, but we couldn't update your profile. Please try again."
                Log.settings.error("Saving profile after identity verification failed: \(error, privacy: .public)")
            }
        }
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

    private var statusLabel: String {
        switch appState.user.verificationStatus {
        case .unverified: return "Not verified"
        case .inProgress: return "In progress"
        case .verified: return "Verified"
        case .failed: return "Failed"
        }
    }

    private func settingsRow(title: String, value: String, valueColor: Color = Theme.foreground, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                LabelValue(label: title, value: value)
                Spacer()
                Image(systemName: icon)
                    .symbolStyle(DesignTokens.TextStyles.body)
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(.horizontal, DesignTokens.Space.s6)
            .padding(.vertical, DesignTokens.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
