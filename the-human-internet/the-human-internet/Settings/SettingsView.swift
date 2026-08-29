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
    @State private var showFeedback = false
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
                    Divider().overlay(Color.white.opacity(0.08))
                    settingsRow(title: "Privacy", value: appState.user.privacy.rawValue, icon: "pencil") {
                        showPrivacySheet = true
                    }
                    Divider().overlay(Color.white.opacity(0.08))
                    settingsRow(title: "Verification Status", value: statusLabel, valueColor: statusColor, icon: "info.circle") {
                        showVerificationInfo = true
                    }
                    Divider().overlay(Color.white.opacity(0.08))

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
                            title: "Identity Verification",
                            value: "Verify Identity",
                            valueColor: Theme.accentBlue,
                            icon: "chevron.right"
                        ) {
                            showIdentityVerification = true
                        }
                        Divider().overlay(Color.white.opacity(0.08))
                    }

                    // Leaves the app on purpose: a Discord invite needs the
                    // user's own logged-in Discord session, so it belongs in
                    // the Discord app (or Safari), not a WKWebView.
                    settingsRow(
                        title: "Contact Us",
                        value: "Join our Discord",
                        valueColor: Theme.accentBlue,
                        icon: "arrow.up.right"
                    ) {
                        UIApplication.shared.open(ExternalLink.discord)
                    }
                    Divider().overlay(Color.white.opacity(0.08))

                    settingsRow(
                        title: "Feedback",
                        value: "Share an idea or issue",
                        valueColor: Theme.accentBlue,
                        icon: "chevron.right"
                    ) {
                        showFeedback = true
                    }
                    Divider().overlay(Color.white.opacity(0.08))

                    Button {
                        showSignOutConfirmation = true
                    } label: {
                        HStack {
                            Text("Log Out")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.red)
                            Spacer()
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }

                    Spacer()
                }
                .padding(.top, 8)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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

    private var statusColor: Color {
        switch appState.user.verificationStatus {
        // Neutral rather than amber: being unverified is a supported resting
        // state — neither something gone wrong nor something in flight that
        // the user should be watching.
        case .unverified: return Theme.textSecondary
        case .inProgress: return Theme.warning
        case .verified: return Theme.success
        case .failed: return .red
        }
    }

    private func settingsRow(title: String, value: String, valueColor: Color = .white, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Text(value)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(valueColor)
                }
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
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
