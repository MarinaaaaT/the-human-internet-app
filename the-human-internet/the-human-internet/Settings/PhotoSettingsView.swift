//
//  PhotoSettingsView.swift
//  the-human-internet
//

import SwiftUI

/// Settings → Photo settings: what happens to a photo on capture (the
/// visible fingerprint) and, for a verified user, what's shown alongside it
/// on its verification page.
struct PhotoSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var watermarkErrorMessage: String?
    /// Whether "Full name" can be offered at all. Loaded on open, like
    /// Profile settings' Full name row.
    @State private var verifiedIdentity: VerifiedIdentity?
    @State private var isLoadingVerifiedIdentity = true
    @State private var nameErrorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    privacyCallout

                    Toggle(isOn: watermarkBinding) {
                        LabelValue(label: "Visible fingerprint", value: "New photos are visually watermarked.")
                    }
                    .tint(Theme.foreground)
                    .padding(.horizontal, DesignTokens.Space.s6)
                    .padding(.vertical, DesignTokens.Space.s4)

                    if let watermarkErrorMessage {
                        errorText(watermarkErrorMessage)
                    }
                    Divider().overlay(Theme.border)

                    if appState.canCustomizeVerificationPage {
                        verificationPageSection
                    }
                }
                .padding(.top, DesignTokens.Space.s2)
            }
        }
        .settingsTitle("Photo settings")
        .task(id: appState.canCustomizeVerificationPage) {
            guard appState.canCustomizeVerificationPage else { return }
            await loadVerifiedIdentity()
        }
    }

    // MARK: - Privacy

    /// What a shared link shows comes down to account privacy before
    /// anything on this page, so it leads, and opens the page that changes it.
    private var privacyCallout: some View {
        NavigationLink(value: SettingsPage.account) {
            HumanCard(radius: DesignTokens.Radius.md) {
                HStack(spacing: DesignTokens.Space.s3) {
                    Text(privacyCalloutText)
                        .textStyle(DesignTokens.TextStyles.label)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .symbolStyle(DesignTokens.TextStyles.label)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Account settings.")
        .padding(.horizontal, DesignTokens.Space.s6)
        .padding(.vertical, DesignTokens.Space.s4)
    }

    private var privacyCalloutText: String {
        switch appState.user.privacy {
        case .humansOnly:
            return "Your account privacy is “Humans Only” so shared links will hide your photo and username. Switch to public in account settings."
        case .public_:
            return "Your account privacy is public so anyone with the link can see your photo and profile information."
        }
    }

    // MARK: - Verification page

    /// Which name the verification page shows, backed by
    /// `users.show_identity`. The username shows either way (for a Public
    /// owner); "Full name" adds the Stripe-verified name beside it. The name
    /// itself is never typed — see `VerifiedNameSheet`.
    private enum PageName: CaseIterable, Identifiable {
        case fullName
        case username

        var id: Self { self }

        var title: String {
            switch self {
            case .fullName: return "Full name"
            case .username: return "Username"
            }
        }
    }

    private var verificationPageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabelValue(
                label: "What do you want to share?",
                value: "Settings below change what is visible when you share verification links to your photos. However, your username is irreversibly added to your photo data."
            )
            .padding(.horizontal, DesignTokens.Space.s6)
            .padding(.vertical, DesignTokens.Space.s4)

            nameRow

            // Every saved handle is shown, so this lists them all and
            // opens the page that edits them.
            NavigationLink(value: SettingsPage.profile) {
                SettingsRowLabel(title: "Social media", value: socialSummary, systemImage: "chevron.right")
            }
            .buttonStyle(.plain)
        }
    }

    /// Only a menu when there's a choice to make. Without a verified name on
    /// file, "Full name" would publish nothing, which reads as a bug rather
    /// than as the honest "we have no verified name for you" it actually is.
    @ViewBuilder
    private var nameRow: some View {
        if verifiedIdentity != nil {
            Menu {
                Picker("Identity information", selection: nameBinding) {
                    ForEach(PageName.allCases) { name in
                        Text(name.title).tag(name)
                    }
                }
            } label: {
                SettingsRowLabel(title: "Identity information", value: currentName.title, systemImage: "chevron.up.chevron.down")
            }
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Space.s1) {
                LabelValue(label: "Identity information", value: PageName.username.title)
                if !isLoadingVerifiedIdentity {
                    Text("No verified name on file.")
                        .textStyle(DesignTokens.TextStyles.label)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Space.s6)
            .padding(.vertical, DesignTokens.Space.s4)
        }

        if let nameErrorMessage {
            errorText(nameErrorMessage)
        }
    }

    /// Belt and braces: a saved `true` with no name on file shows as
    /// Username, because that's what the page actually renders.
    private var currentName: PageName {
        appState.user.showIdentity && verifiedIdentity != nil ? .fullName : .username
    }

    private var socialSummary: String {
        let links = appState.user.socialLinks.items
        guard !links.isEmpty else { return "None yet. Add them in Profile settings." }
        return links.map { "\($0.platform.displayName): \($0.handle)" }.joined(separator: "\n")
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .textStyle(DesignTokens.TextStyles.label)
            .foregroundStyle(Theme.destructive)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Space.s6)
            .padding(.bottom, DesignTokens.Space.s3)
    }

    // MARK: - Saving

    /// Writes through on every flip, optimistic with revert — there's no
    /// Save button for a switch.
    private var watermarkBinding: Binding<Bool> {
        Binding(
            get: { appState.isWatermarkEnabled },
            set: { enabled in
                watermarkErrorMessage = nil
                Task {
                    do {
                        try await appState.setWatermarkEnabled(enabled)
                    } catch {
                        watermarkErrorMessage = "Couldn't save — please try again."
                        Log.settings.error("Photo Fingerprint update failed: \(error, privacy: .public)")
                    }
                }
            }
        )
    }

    /// Same as the switch: written on selection, optimistic with revert.
    private var nameBinding: Binding<PageName> {
        Binding(
            get: { currentName },
            set: { name in
                let showIdentity = name == .fullName
                let previous = appState.user.showIdentity
                guard showIdentity != previous else { return }
                nameErrorMessage = nil
                var updated = appState.user
                updated.showIdentity = showIdentity
                appState.user.showIdentity = showIdentity
                Task {
                    do {
                        try await UserProfileRepository.upsert(updated)
                    } catch {
                        appState.user.showIdentity = previous
                        nameErrorMessage = "Couldn't save — please try again."
                        Log.settings.error("Verification page name update failed: \(error, privacy: .public)")
                    }
                }
            }
        )
    }

    /// A failed read leaves "Full name" unavailable rather than showing an
    /// error — the same outcome as having no name on file.
    private func loadVerifiedIdentity() async {
        defer { isLoadingVerifiedIdentity = false }
        guard let userID = appState.user.id else { return }
        do {
            verifiedIdentity = try await UserProfileRepository.fetchVerifiedIdentity(userID: userID)
        } catch {
            Log.settings.error("Reading the verified name failed: \(error, privacy: .public)")
        }
    }
}

#Preview {
    NavigationStack {
        PhotoSettingsView()
            .environment(AppState())
    }
}
