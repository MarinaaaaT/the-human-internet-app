//
//  VerificationPageSheet.swift
//  the-human-internet
//

import SwiftUI

/// Lets a **verified** user decide what sits alongside their photo on the
/// signed-out verification page: their real name, and up to
/// `SocialLink.maxCount` social handles.
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
    @State private var firstName = ""
    @State private var lastName = ""
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

            Toggle(isOn: $showIdentity) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show my name")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Your verified first and last name, shown publicly.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accentBlue)

            // The fields only exist while the toggle is on: a name typed
            // into a disabled form reads as "saved and hidden", which is
            // exactly the ambiguity to avoid on the one screen that decides
            // whether a legal name goes on the public internet.
            if showIdentity {
                HITextField(placeholder: "First name", text: $firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                HITextField(placeholder: "Last name", text: $lastName)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
            }
        }
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
        firstName = user.displayFirstName
        lastName = user.displayLastName
        links = user.socialLinks.items
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
        updated.showIdentity = showIdentity
        updated.displayFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.displayLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.socialLinks = SocialLinks(normalized)

        if updated.showIdentity, updated.displayName.isEmpty {
            errorMessage = "Add your name, or turn “Show my name” off."
            return
        }

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
