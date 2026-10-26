//
//  ProfileSettingsView.swift
//  the-human-internet
//

import SwiftUI

/// Settings → Profile settings: who you are on the human internet. Your
/// username, your identity verification, and — once verified — the name
/// Stripe verified and the social handles your verification page can link
/// to. *Whether* those are published is chosen in Photo settings.
struct ProfileSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var showEditUsername = false
    @State private var showVerificationInfo = false
    @State private var showIdentityVerification = false
    @State private var showVerifiedName = false
    /// Read from `users.verified_first_name`/`verified_last_name` when the
    /// page opens for a verified user. `nil` once loaded means Stripe never
    /// gave us a name for this account — see `VerifiedNameSheet`.
    @State private var verifiedIdentity: VerifiedIdentity?
    @State private var isLoadingVerifiedIdentity = true
    @State private var saveErrorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(
                        title: "Username",
                        value: appState.user.username.isEmpty ? "—" : appState.user.username,
                        systemImage: "pencil"
                    ) {
                        showEditUsername = true
                    }
                    Divider().overlay(Theme.border)

                    if showsVerificationStatus {
                        SettingsRow(title: "Identity verification", value: statusLabel, systemImage: "info.circle") {
                            showVerificationInfo = true
                        }
                        Divider().overlay(Theme.border)
                    }

                    if appState.canCustomizeVerificationPage {
                        SettingsRow(title: "Full name", value: fullNameLabel, systemImage: "info.circle") {
                            showVerifiedName = true
                        }
                        // Until the read lands the sheet couldn't say whether
                        // there's a name on file or not.
                        .disabled(isLoadingVerifiedIdentity)
                        Divider().overlay(Theme.border)

                        SocialHandlesEditor()
                    } else if showsVerificationPitch || canStartVerification {
                        verificationPitch
                    }
                }
                .padding(.top, DesignTokens.Space.s2)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .settingsTitle("Profile settings")
        // Keyed on the gate so a verification that lands while the page is
        // open (Settings polls an in-progress status) loads the name then.
        .task(id: appState.canCustomizeVerificationPage) {
            guard appState.canCustomizeVerificationPage else { return }
            await loadVerifiedIdentity()
        }
        .sheet(isPresented: $showEditUsername) {
            EditUsernameSheet()
        }
        .sheet(isPresented: $showVerificationInfo) {
            VerificationStatusSheet(status: appState.user.verificationStatus)
        }
        .sheet(isPresented: $showVerifiedName) {
            VerifiedNameSheet(identity: verifiedIdentity)
        }
        .sheet(isPresented: $showIdentityVerification) {
            // "Not now" rather than "Skip": there's no flow to skip past here,
            // the sheet just closes and the button stays available.
            IdentityVerificationView(
                skipTitle: "Not now",
                onSkip: { showIdentityVerification = false },
                onFinish: {
                    showIdentityVerification = false
                    // Unlike onboarding, nothing else upserts afterwards — the
                    // now-.inProgress status has to be persisted here or it's
                    // lost on relaunch.
                    saveProfile()
                }
            )
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

    // MARK: - Not yet verified

    /// "ID Verification in Settings" off hides the row too, but only from an
    /// `unverified` user: with nothing to act on, "Not verified" would only
    /// point at a door that's shut. Any other status stays — it's true and
    /// useful whether or not they can act on it.
    private var showsVerificationStatus: Bool {
        appState.isIdentityVerificationInSettingsEnabled || appState.user.verificationStatus != .unverified
    }

    /// What verifying would unlock. Pitches the same thing the button below
    /// offers, so it goes with the same flag.
    private var showsVerificationPitch: Bool {
        appState.isIdentityVerificationInSettingsEnabled && appState.user.verificationStatus != .verified
    }

    /// Verification is optional and skippable during onboarding, so this is
    /// the way back to it — gated twice, for two unrelated reasons:
    ///
    /// - "ID Verification in Settings" is this door's own switch, separate
    ///   from onboarding's, so either can be shut without the other.
    /// - Only offered to someone who hasn't started — an in-progress user is
    ///   waiting on the webhook, and restarting would just orphan their
    ///   session.
    private var canStartVerification: Bool {
        appState.isIdentityVerificationInSettingsEnabled && appState.user.verificationStatus == .unverified
    }

    private var verificationPitch: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s6) {
            if showsVerificationPitch {
                Text("After verifying your identity you will have the option of sharing your social accounts and your full name alongside your photos.")
                    .textStyle(DesignTokens.TextStyles.body)
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canStartVerification {
                SecondaryButton(title: "Verify identity") {
                    showIdentityVerification = true
                }
            }
        }
        .padding(.horizontal, DesignTokens.Space.s6)
        .padding(.vertical, DesignTokens.Space.s6)
    }

    // MARK: - Labels

    private var statusLabel: String {
        switch appState.user.verificationStatus {
        case .unverified: return "Not verified"
        case .inProgress: return "Pending"
        case .verified: return "Verified"
        case .failed: return "Failed"
        }
    }

    private var fullNameLabel: String {
        if isLoadingVerifiedIdentity { return "Checking…" }
        return verifiedIdentity?.displayName ?? "Not on file"
    }

    // MARK: - Actions

    /// A failed read is reported as "not on file" rather than as an error —
    /// the consequence is the same, and it keeps the page usable for
    /// editing handles, which is the rest of what it's for.
    private func loadVerifiedIdentity() async {
        defer { isLoadingVerifiedIdentity = false }
        guard let userID = appState.user.id else { return }
        do {
            verifiedIdentity = try await UserProfileRepository.fetchVerifiedIdentity(userID: userID)
        } catch {
            Log.settings.error("Reading the verified name failed: \(error, privacy: .public)")
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
}

/// Up to `SocialLink.maxCount` handles for the verification page to link to.
/// **No Save button**: a change is written once the user leaves the field,
/// or after `typingPause` without typing, and at once for a platform change
/// or a removal.
///
/// Everything goes out in one `UserProfileRepository.upsert` of the whole
/// user row, like the rest of Settings. That makes handle validation
/// load-bearing rather than a nicety: `users_social_links_check` rejects the
/// *entire* row, so one stray character would fail a save that also carries
/// the username and privacy. An invalid handle is reported and not sent.
private struct SocialHandlesEditor: View {
    @Environment(AppState.self) private var appState

    @State private var links: [SocialLink] = []
    @FocusState private var focusedLinkID: SocialLink.ID?
    @State private var pendingSave: Task<Void, Never>?
    /// Saves run one after another, so two in flight can't land out of
    /// order and leave the older list in the database.
    @State private var lastSave: Task<Void, Never>?
    /// What was last sent, so a pause followed by leaving the field doesn't
    /// write the same list twice. Starts as what's already saved.
    @State private var lastSubmitted: [SocialLink]?
    @State private var errorMessage: String?

    private static let typingPause: Duration = .seconds(3)

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
            LabelValue(
                label: "Social handles",
                value: "Just the handle — if you choose to share it alongside your photos, we'll link directly to your profiles. Up to \(SocialLink.maxCount)."
            )

            ForEach($links) { $link in
                row(link: $link)
            }

            if links.count < SocialLink.maxCount {
                Button {
                    let link = SocialLink(platform: nextUnusedPlatform)
                    links.append(link)
                    focusedLinkID = link.id
                } label: {
                    HStack(spacing: DesignTokens.Space.s2) {
                        Image(systemName: "plus")
                            .symbolStyle(DesignTokens.TextStyles.label)
                        Text("Add handle")
                            .textStyle(DesignTokens.TextStyles.label)
                    }
                    .padding(.horizontal, DesignTokens.Space.s6)
                    .ctaStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let errorMessage {
                Text(errorMessage)
                    .textStyle(DesignTokens.TextStyles.label)
                    .foregroundStyle(Theme.destructive)
            }
        }
        .padding(.horizontal, DesignTokens.Space.s6)
        .padding(.vertical, DesignTokens.Space.s4)
        .onAppear {
            links = appState.user.socialLinks.items
            lastSubmitted = links
        }
        .onChange(of: focusedLinkID) { left, _ in
            guard let left else { return }
            // Tidy what they typed ("@marina" → "marina") as they leave it.
            if let index = links.firstIndex(where: { $0.id == left }) {
                links[index].handle = SocialLink.normalize(handle: links[index].handle)
            }
            saveNow()
        }
        // Leaving the page mid-pause would otherwise drop the last edit.
        .onDisappear(perform: saveNow)
    }

    private func row(link: Binding<SocialLink>) -> some View {
        HStack(spacing: DesignTokens.Space.s3) {
            Menu {
                Picker("Platform", selection: Binding(
                    get: { link.wrappedValue.platform },
                    set: { link.wrappedValue.platform = $0; saveNow() }
                )) {
                    ForEach(SocialPlatform.allCases) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }
            } label: {
                HStack(spacing: DesignTokens.Space.s1) {
                    Text(link.wrappedValue.platform.displayName)
                        .textStyle(DesignTokens.TextStyles.label)
                    Image(systemName: "chevron.down")
                        .symbolStyle(DesignTokens.TextStyles.caption)
                }
                .padding(.horizontal, DesignTokens.Space.s4)
                .ctaStyle(.secondary)
            }

            HITextField(
                placeholder: link.wrappedValue.platform.handlePlaceholder,
                text: Binding(
                    get: { link.wrappedValue.handle },
                    set: { link.wrappedValue.handle = $0; scheduleSave() }
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($focusedLinkID, equals: link.wrappedValue.id)

            Button {
                links.removeAll { $0.id == link.wrappedValue.id }
                saveNow()
            } label: {
                Image(systemName: "minus.circle")
                    .symbolStyle(DesignTokens.TextStyles.title)
                    .foregroundStyle(Theme.foreground)
                    .frame(width: DesignTokens.Size.minTouch, height: DesignTokens.Size.minTouch)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove handle")
        }
    }

    /// Seeds a new row with a platform the user hasn't used yet, so the
    /// common case (one handle per platform) needs no trip through the
    /// picker. Falls back to the first platform once they're all taken —
    /// nothing stops two rows sharing one, the database included.
    private var nextUnusedPlatform: SocialPlatform {
        let used = Set(links.map(\.platform))
        return SocialPlatform.allCases.first { !used.contains($0) } ?? .instagram
    }

    // MARK: - Saving

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: Self.typingPause)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    /// Snapshots the list *now*, while the view is certainly on screen, and
    /// only the write itself happens later — so a save started by leaving
    /// the page still sends what was on it.
    private func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil

        // A row the user added and left blank is an abandoned row, not an
        // error — dropped silently (and kept on screen, in case they're
        // about to fill it in). Anything actually typed has to be valid,
        // because the CHECK constraint would otherwise reject the whole row
        // with a Postgres error nobody can act on.
        let normalized = links
            .map { SocialLink(platform: $0.platform, handle: SocialLink.normalize(handle: $0.handle)) }
            .filter { !$0.handle.isEmpty }

        if let invalid = normalized.first(where: { !$0.isValid }) {
            errorMessage = "\(invalid.platform.displayName) handles can only contain letters, numbers, dots, dashes and underscores."
            return
        }
        errorMessage = nil

        if let lastSubmitted, Self.sameHandles(normalized, lastSubmitted) { return }
        lastSubmitted = normalized

        var updated = appState.user
        updated.socialLinks = SocialLinks(normalized)
        let appState = appState
        lastSave = Task { [previous = lastSave] in
            await previous?.value
            do {
                try await UserProfileRepository.upsert(updated)
                // Just this field — the rest of `appState.user` may have
                // moved on (a status refresh) since the snapshot was taken.
                appState.user.socialLinks = updated.socialLinks
            } catch {
                // Forget what was sent, so the next edit retries it.
                lastSubmitted = nil
                errorMessage = "Couldn't save — please try again."
                Log.settings.error("Social handles update failed: \(error, privacy: .public)")
            }
        }
    }

    /// `SocialLink`'s own `==` compares its per-session `id` too.
    private static func sameHandles(_ a: [SocialLink], _ b: [SocialLink]) -> Bool {
        a.elementsEqual(b) { $0.platform == $1.platform && $0.handle == $1.handle }
    }
}

#Preview {
    NavigationStack {
        ProfileSettingsView()
            .environment(AppState())
    }
}
