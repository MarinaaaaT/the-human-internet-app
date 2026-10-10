//
//  VerificationPageSheet.swift
//  the-human-internet
//

import SwiftUI

/// Lets a **verified** user decide what sits alongside their photo on the
/// signed-out verification page: their real name, and up to
/// `SocialLink.maxCount` social handles.
///
/// The name is **shown, not entered**. It comes from Stripe Identity's
/// `verified_outputs`, stored by `stripe-identity-webhook` under the service
/// role and guarded by triggers against any client write. The page renders
/// it beside "taken by a real, verified human", so a name typed here would
/// be a claim wearing our checkmark — which is exactly what an earlier
/// version of this screen allowed. The toggle chooses whether it is
/// published; nothing chooses what it says.
///
/// Reachable only from the Settings row that `verification_status ==
/// .verified` gates, and that gate is presentation only — the one that binds
/// is `get_verification_photo()`, which withholds every field edited here
/// unless the column says `verified`. Nothing typed into this sheet asserts
/// anything; it decorates a claim the server already made.
///
/// Everything is saved in one `UserProfileRepository.upsert` of the whole
/// user row, like the other Settings sheets. That makes handle validation
/// load-bearing rather than a nicety: `users_social_links_check` rejects the
/// *entire* row, so one stray character would fail a save that also carries
/// the username and privacy.
struct VerificationPageSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showIdentity = false
    /// Read from `users.verified_first_name`/`verified_last_name` when the
    /// sheet opens. `nil` once loaded means Stripe never gave us a name for
    /// this account — see `identitySection`.
    @State private var verifiedIdentity: VerifiedIdentity?
    @State private var isLoadingVerifiedIdentity = true
    @State private var links: [SocialLink] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Space.s6) {
                    SheetGrabber()

                    header

                    identitySection

                    socialSection

                    if appState.user.privacy == .humansOnly {
                        privacyNote
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .textStyle(DesignTokens.TextStyles.label)
                            .foregroundStyle(Theme.destructive)
                    }

                    PrimaryButton(title: isSaving ? "Saving…" : "Save", isEnabled: !isSaving) {
                        save()
                    }
                }
                .padding(DesignTokens.Space.s6)
                .padding(.top, DesignTokens.Space.s4)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .onAppear(perform: loadFromUser)
        .task { await loadVerifiedIdentity() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
            Text("Verification page")
                .textStyle(DesignTokens.TextStyles.h3)
                .foregroundStyle(Theme.foreground)
            Text("Choose what people see next to your photo at \(VerifiedPhoto.webHost).")
                .textStyle(DesignTokens.TextStyles.label)
                .foregroundStyle(Theme.mutedForeground)
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
            FieldLabel(text: "Identity")

            // Disabled until the name is known, and permanently if there
            // isn't one: switching it on would publish nothing, which reads
            // as a bug rather than as the honest "we have no verified name
            // for you" it actually is.
            Toggle(isOn: $showIdentity) {
                VStack(alignment: .leading, spacing: DesignTokens.Space.s1) {
                    Text("Show my verified name")
                        .textStyle(DesignTokens.TextStyles.body)
                        .foregroundStyle(Theme.foreground)
                    Text(identitySubtitle)
                        .textStyle(DesignTokens.TextStyles.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .tint(Theme.foreground)
            .disabled(isLoadingVerifiedIdentity || verifiedIdentity == nil)

            if let verifiedIdentity {
                HumanCard(radius: DesignTokens.Radius.md) {
                    HStack(alignment: .top, spacing: DesignTokens.Space.s2) {
                        BrandMark(size: DesignTokens.Space.s4)
                        // Exactly what a viewer sees on the verification page —
                        // same `VerifiedIdentity`, same sentence.
                        Text(verifiedIdentity.statement ?? verifiedIdentity.displayName)
                            .textStyle(verifiedIdentity.statement == nil ? DesignTokens.TextStyles.title : DesignTokens.TextStyles.label)
                            .foregroundStyle(verifiedIdentity.statement == nil ? Theme.foreground : Theme.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            } else if !isLoadingVerifiedIdentity {
                Text("We don't have a verified name on file for your account. It's captured during identity verification — if yours predates that, it'll appear after your next verification.")
                    .textStyle(DesignTokens.TextStyles.label)
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(DesignTokens.Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            }
        }
    }

    private var identitySubtitle: String {
        if isLoadingVerifiedIdentity { return "Checking…" }
        return verifiedIdentity == nil
            ? "No verified name on file."
            : "The name Stripe verified against your ID. You can't edit it here."
    }

    private var socialSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
            FieldLabel(text: "Social handles")

            Text("Just the handle — we build the link. Up to \(SocialLink.maxCount).")
                .textStyle(DesignTokens.TextStyles.caption)
                .foregroundStyle(Theme.mutedForeground)

            ForEach($links) { $link in
                socialRow(link: $link)
            }

            if links.count < SocialLink.maxCount {
                Button {
                    links.append(SocialLink(platform: nextUnusedPlatform))
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
        }
    }

    private func socialRow(link: Binding<SocialLink>) -> some View {
        HStack(spacing: DesignTokens.Space.s3) {
            Menu {
                Picker("Platform", selection: link.platform) {
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
                text: link.handle
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                links.removeAll { $0.id == link.wrappedValue.id }
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

    private var privacyNote: some View {
        Text("Your privacy is set to Humans Only, so your verification page hides your photo and username from signed-out visitors — and it hides this too. Switch to Public for any of it to show.")
            .textStyle(DesignTokens.TextStyles.label)
            .foregroundStyle(Theme.foreground)
            .padding(DesignTokens.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
    }

    // MARK: - State

    /// Seeds a new row with a platform the user hasn't used yet, so the
    /// common case (one handle per platform) needs no trip through the
    /// picker. Falls back to the first platform once they're all taken —
    /// nothing stops two rows sharing one, the database included.
    private var nextUnusedPlatform: SocialPlatform {
        let used = Set(links.map(\.platform))
        return SocialPlatform.allCases.first { !used.contains($0) } ?? .instagram
    }

    private func loadFromUser() {
        let user = appState.user
        showIdentity = user.showIdentity
        links = user.socialLinks.items
    }

    /// A failed read is reported as "no name on file" rather than as an
    /// error. The consequence is the same — the toggle stays off — and it
    /// keeps the sheet usable for editing handles, which is the rest of what
    /// it's for.
    private func loadVerifiedIdentity() async {
        defer { isLoadingVerifiedIdentity = false }
        guard let userID = appState.user.id else { return }
        do {
            verifiedIdentity = try await UserProfileRepository.fetchVerifiedIdentity(userID: userID)
        } catch {
            Log.settings.error("Reading the verified name failed: \(error, privacy: .public)")
        }
    }

    private func save() {
        errorMessage = nil

        // A row the user added and then left blank is an abandoned row, not
        // an error — dropped silently. Anything actually typed has to be
        // valid, because the CHECK constraint would otherwise reject the
        // whole row with a Postgres error nobody can act on.
        let normalized = links
            .map { SocialLink(platform: $0.platform, handle: SocialLink.normalize(handle: $0.handle)) }
            .filter { !$0.handle.isEmpty }

        if let invalid = normalized.first(where: { !$0.isValid }) {
            errorMessage = "\(invalid.platform.displayName) handles can only contain letters, numbers, dots, dashes and underscores."
            return
        }

        var updated = appState.user
        // Belt and braces: the toggle is already disabled without a verified
        // name, but a saved `true` with nothing to show would leave the user
        // believing their name is published when the page renders nothing.
        updated.showIdentity = showIdentity && verifiedIdentity != nil
        updated.socialLinks = SocialLinks(normalized)

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await UserProfileRepository.upsert(updated)
                appState.user = updated
                dismiss()
            } catch {
                errorMessage = "Couldn't save — please try again."
                Log.settings.error("Verification page update failed: \(error, privacy: .public)")
            }
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        VerificationPageSheet()
            .environment(AppState())
    }
}
