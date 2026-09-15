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
    @State private var verifiedName: String?
    @State private var isLoadingVerifiedName = true
    @State private var links: [SocialLink] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SheetGrabber()

                    header

                    identitySection

                    socialSection

                    if appState.user.privacy == .humansOnly {
                        privacyNote
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }

                    PrimaryButton(title: isSaving ? "Saving…" : "Save", isEnabled: !isSaving) {
                        save()
                    }
                }
                .padding(24)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .onAppear(perform: loadFromUser)
        .task { await loadVerifiedName() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Verification Page")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Text("Choose what people see next to your photo at \(VerifiedPhoto.webHost).")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: "IDENTITY")

            // Disabled until the name is known, and permanently if there
            // isn't one: switching it on would publish nothing, which reads
            // as a bug rather than as the honest "we have no verified name
            // for you" it actually is.
            Toggle(isOn: $showIdentity) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show my verified name")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Text(identitySubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accentBlue)
            .disabled(isLoadingVerifiedName || verifiedName == nil)

            if let verifiedName {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.success)
                    Text(verifiedName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(14)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if !isLoadingVerifiedName {
                Text("We don't have a verified name on file for your account. It's captured during identity verification — if yours predates that, it'll appear after your next verification.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var identitySubtitle: String {
        if isLoadingVerifiedName { return "Checking…" }
        return verifiedName == nil
            ? "No verified name on file."
            : "The name Stripe verified against your ID. You can't edit it here."
    }

    private var socialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: "SOCIAL HANDLES")

            Text("Just the handle — we build the link. Up to \(SocialLink.maxCount).")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            ForEach($links) { $link in
                socialRow(link: $link)
            }

            if links.count < SocialLink.maxCount {
                Button {
                    links.append(SocialLink(platform: nextUnusedPlatform))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                        Text("Add handle")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(Theme.accentBlue)
                }
            }
        }
    }

    private func socialRow(link: Binding<SocialLink>) -> some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Platform", selection: link.platform) {
                    ForEach(SocialPlatform.allCases) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(link.wrappedValue.platform.displayName)
                        .font(.system(size: 14, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(minWidth: 108, alignment: .leading)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var privacyNote: some View {
        Text("Your privacy is set to Humans Only, so your verification page hides your photo and username from signed-out visitors — and it hides this too. Switch to Public for any of it to show.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.warning)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
    private func loadVerifiedName() async {
        defer { isLoadingVerifiedName = false }
        guard let userID = appState.user.id else { return }
        do {
            verifiedName = try await UserProfileRepository.fetchVerifiedName(userID: userID)
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
        updated.showIdentity = showIdentity && verifiedName != nil
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
