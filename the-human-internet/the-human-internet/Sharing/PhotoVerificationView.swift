//
//  PhotoVerificationView.swift
//  the-human-internet
//

import SwiftUI

/// Opened by tapping a photo link (`thehumaninternet://photo/{id}`, later a
/// real `the-human-internet.com/{id}` Universal Link) to view someone else's
/// photo. Read-only — presented over whatever's on screen, not part of any
/// tab's navigation stack, per the product design: dismissing it just closes
/// it, and the link has to be tapped again to reopen it.
///
/// Shows what the public page at `the-human-internet.com/{code}` shows: the
/// owner's username, and — when they're verified and have opted in — the
/// name Stripe verified and their social handles. Every one of those gates
/// is applied inside `get_photo_owner_profile()`, never here.
///
/// The two pages differ in exactly one way, deliberately. This one has no
/// privacy gate: per the PRD a signed-in app user sees full contents whether
/// the owner is `Public` or `Humans Only`, because that setting separates
/// humans from the open internet rather than humans from each other.
struct PhotoVerificationView: View {
    let photoID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var photo: VerifiedPhoto?
    /// Loaded alongside the photo. Stays nil if the owner lookup fails,
    /// which costs the caption and the handles but still shows the photo and
    /// the verified claim — the part that matters.
    @State private var owner: PhotoOwnerProfile?
    @State private var isLoading = true
    @State private var showLearnMore = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
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
                }
                .padding(.horizontal, DesignTokens.Space.s6)
                .padding(.top, DesignTokens.Space.s3)

                Group {
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .tint(Theme.foreground)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else if let photo {
                        content(for: photo)
                    } else {
                        Spacer()
                        notFound
                        Spacer()
                    }
                }
            }
        }
        .sheet(isPresented: $showLearnMore) {
            PhotoVerificationInfoSheet()
        }
        .task(id: photoID) {
            await load()
        }
    }

    private func content(for photo: VerifiedPhoto) -> some View {
        Group {
            VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
                HumanCard(radius: DesignTokens.Radius.md) {
                    HStack(spacing: DesignTokens.Space.s3) {
                        // "Verified" is always the spiral, never a check.
                        BrandMark(size: DesignTokens.Size.icon)
                        Text("This photo was taken by a real human!")
                            .textStyle(DesignTokens.TextStyles.title)
                            .foregroundStyle(Theme.foreground)
                    }
                }

                Button {
                    showLearnMore = true
                } label: {
                    (
                        Text("How do you know? ")
                            .foregroundStyle(Theme.mutedForeground)
                        + Text("Click here to learn more.")
                            .foregroundStyle(Theme.foreground)
                            .underline()
                    )
                    .textStyle(DesignTokens.TextStyles.label)
                }
            }
            .padding(.horizontal, DesignTokens.Space.s6)

            // `.fit` (not `.fill`) — the source images are full-resolution camera
            // photos, and `.fill` scales up to cover, overflowing its bounds and
            // painting over the header above it.
            RemotePhotoImage(photo: photo, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
                .padding(.horizontal, DesignTokens.Space.s6)
                .padding(.top, DesignTokens.Space.s1)

            if let owner {
                ownerDetails(owner, capturedAt: photo.capturedAt)
                    .padding(.horizontal, DesignTokens.Space.s6)
                    .padding(.top, DesignTokens.Space.s3)
            }

            Spacer()
        }
    }

    /// Mirrors the layout of the website's verification page: the caption
    /// line, then the verified name, then the handles as chips.
    private func ownerDetails(_ owner: PhotoOwnerProfile, capturedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
            Text(caption(for: owner, capturedAt: capturedAt))
                .textStyle(DesignTokens.TextStyles.label)
                .foregroundStyle(Theme.mutedForeground)

            if let identity = owner.verifiedIdentity {
                HStack(alignment: .top, spacing: DesignTokens.Space.s2) {
                    BrandMark(size: DesignTokens.Space.s4)
                    // The full sentence when there's a date to cite,
                    // otherwise the name alone — see `VerifiedIdentity`.
                    Text(identity.statement ?? identity.displayName)
                        .textStyle(identity.statement == nil ? DesignTokens.TextStyles.title : DesignTokens.TextStyles.label)
                        .foregroundStyle(identity.statement == nil ? Theme.foreground : Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }

            if !owner.socialLinks.items.isEmpty {
                // Wraps rather than scrolls: five handles at most, and a
                // horizontal scroller inside a full-screen cover competes
                // with the dismiss gesture.
                FlowLayout(spacing: DesignTokens.Space.s2) {
                    ForEach(owner.socialLinks.items) { link in
                        socialChip(link)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func caption(for owner: PhotoOwnerProfile, capturedAt: Date) -> String {
        let captured = capturedAt.formatted(.dateTime.month(.wide).day().year())
        return owner.isVerified
            ? "Verified by @\(owner.username) · captured \(captured)"
            : "@\(owner.username) · captured \(captured)"
    }

    /// A handle with no resolvable URL renders as plain text rather than
    /// disappearing — `profileURL` returns nil only for a handle that failed
    /// revalidation, and silently dropping someone's account would be
    /// stranger than showing it flat.
    @ViewBuilder
    private func socialChip(_ link: SocialLink) -> some View {
        let label = HStack(spacing: DesignTokens.Space.s2) {
            Text(link.platform.displayName)
                .foregroundStyle(Theme.mutedForeground)
            Text(link.platform.displayHandle(link.handle))
        }
        .textStyle(DesignTokens.TextStyles.label)
        .padding(.horizontal, DesignTokens.Space.s4)
        .ctaStyle(.secondary)

        if let url = link.platform.profileURL(handle: link.handle) {
            Link(destination: url) { label }
        } else {
            label
        }
    }

    private var notFound: some View {
        VStack(spacing: DesignTokens.Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .symbolStyle(DesignTokens.TextStyles.h2)
                .foregroundStyle(Theme.mutedForeground)
            Text("This photo couldn't be found.")
                .foregroundStyle(Theme.mutedForeground)
                .textStyle(DesignTokens.TextStyles.body)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        isLoading = true
        do {
            photo = try await PhotoRepository.fetch(photoID: photoID)
        } catch {
            Log.photos.error("Verification-view photo fetch failed for \(photoID, privacy: .public): \(error, privacy: .public)")
        }
        isLoading = false

        // Separate, and after: the photo is the point, and a failure to
        // resolve the owner must not leave the viewer staring at a spinner.
        do {
            owner = try await PhotoRepository.fetchOwnerProfile(photoID: photoID)
        } catch {
            Log.photos.error("Verification-view owner fetch failed for \(photoID, privacy: .public): \(error, privacy: .public)")
        }
    }
}

#Preview {
    Color.clear.fullScreenCover(isPresented: .constant(true)) {
        PhotoVerificationView(photoID: UUID())
    }
}
