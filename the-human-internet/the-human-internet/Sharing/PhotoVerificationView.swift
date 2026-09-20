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
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Group {
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .tint(.white)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.success)
                    Text("This photo was taken by a real human!")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Button {
                    showLearnMore = true
                } label: {
                    (
                        Text("How do you know? ")
                            .foregroundStyle(Theme.textSecondary)
                        + Text("Click here to learn more.")
                            .foregroundStyle(.white)
                            .underline()
                    )
                    .font(.system(size: 13))
                }
            }
            .padding(.horizontal, 20)

            // `.fit` (not `.fill`) — the source images are full-resolution camera
            // photos, and `.fill` scales up to cover, overflowing its bounds and
            // painting over the header above it.
            RemotePhotoImage(photo: photo, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 20)
                .padding(.top, 4)

            if let owner {
                ownerDetails(owner, capturedAt: photo.capturedAt)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Spacer()
        }
    }

    /// Mirrors the layout of the website's verification page: the caption
    /// line, then the verified name, then the handles as chips.
    private func ownerDetails(_ owner: PhotoOwnerProfile, capturedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption(for: owner, capturedAt: capturedAt))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            if let identity = owner.verifiedIdentity {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.success)
                    // The full sentence when there's a date to cite,
                    // otherwise the name alone — see `VerifiedIdentity`.
                    Text(identity.statement ?? identity.displayName)
                        .font(.system(size: identity.statement == nil ? 16 : 13))
                        .fontWeight(identity.statement == nil ? .semibold : .regular)
                        .foregroundStyle(identity.statement == nil ? .white : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }

            if !owner.socialLinks.items.isEmpty {
                // Wraps rather than scrolls: five handles at most, and a
                // horizontal scroller inside a full-screen cover competes
                // with the dismiss gesture.
                FlowLayout(spacing: 8) {
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
            ? "verified by @\(owner.username) · captured \(captured)"
            : "@\(owner.username) · captured \(captured)"
    }

    /// A handle with no resolvable URL renders as plain text rather than
    /// disappearing — `profileURL` returns nil only for a handle that failed
    /// revalidation, and silently dropping someone's account would be
    /// stranger than showing it flat.
    @ViewBuilder
    private func socialChip(_ link: SocialLink) -> some View {
        let label = HStack(spacing: 6) {
            Text(link.platform.displayName)
                .foregroundStyle(Theme.textSecondary)
            Text(link.platform.displayHandle(link.handle))
                .foregroundStyle(.white)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 9))

        if let url = link.platform.profileURL(handle: link.handle) {
            Link(destination: url) { label }
        } else {
            label
        }
    }

    private var notFound: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textSecondary)
            Text("This photo couldn't be found.")
                .foregroundStyle(Theme.textSecondary)
                .font(.system(size: 14))
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
