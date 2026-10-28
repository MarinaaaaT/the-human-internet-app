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
/// Tapping the photo shows the website's frosted proof over it (`ProofReveal`)
/// — who took it, their verified name when published, and when — with a
/// download icon that saves the photo to Photos. That's the only place those
/// are shown: under the photo there are just the social handles.
///
/// The page scrolls rather than fitting the screen, so the photo always
/// spans the card above it, however many handles follow it.
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
    /// The photo is zoomed in, and the page around it has faded out to let
    /// it take the whole screen.
    @State private var isPhotoZoomed = false
    /// The proof over the photo. A tap on the photo shows it and another
    /// hides it, as on the website; zooming hides it too.
    @State private var isProofShown = false
    /// The photo as `RemotePhotoImage` loaded it. The proof blurs a copy.
    @State private var loadedImage: UIImage?
    @State private var downloadStatus: ProofDownloadStatus = .ready
    @State private var downloadError: String?
    /// What the scroll view has on screen, in its content's coordinates —
    /// where the zoom layer has to be for a zoomed photo to fill the screen.
    @State private var viewport: CGRect = .zero

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Group {
                if isLoading {
                    ProgressView()
                        .tint(Theme.foreground)
                } else if let photo {
                    ScrollView {
                        content(for: photo)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    // A zoomed photo pans; the page under it stays put.
                    .scrollDisabled(isPhotoZoomed)
                    .onScrollGeometryChange(for: CGRect.self, of: \.visibleRect) { _, visibleRect in
                        viewport = visibleRect
                    }
                } else {
                    notFound
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                closeBar
            }
        }
        // It fades out with the page; back at 1x, the photo comes back bare.
        .onChange(of: isPhotoZoomed) { _, isZoomed in
            if isZoomed { isProofShown = false }
        }
        .sheet(isPresented: $showLearnMore) {
            PhotoVerificationInfoSheet()
        }
        .alert(
            "Couldn't download photo",
            isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })
        ) {
            Button("OK") { downloadError = nil }
        } message: {
            Text(downloadError ?? "Please try again.")
        }
        .task(id: photoID) {
            await load()
        }
    }

    /// Pinned over the page, which scrolls under it. Opaque, so nothing —
    /// the photo in the zoom layer included — shows through behind Close.
    private var closeBar: some View {
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
        .padding(.bottom, DesignTokens.Space.s4)
        .background(Theme.background.ignoresSafeArea())
        // A zoomed photo is zoomed back out first.
        .fadesWhilePhotoZoomed(isPhotoZoomed)
    }

    private func content(for photo: VerifiedPhoto) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
                HumanCard(radius: DesignTokens.Radius.md) {
                    HStack(spacing: DesignTokens.Space.s3) {
                        if owner?.isDemo == true {
                            // No spiral: the spiral means verified, and this
                            // is the one box that says it isn't guaranteed.
                            Text(DemoAccount.verificationDisclaimer)
                                .textStyle(DesignTokens.TextStyles.title)
                                .foregroundStyle(Theme.foreground)
                        } else {
                            // "Verified" is always the spiral, never a check.
                            BrandMark(size: DesignTokens.Size.icon)
                            Text("This photo was taken by a real human!")
                                .textStyle(DesignTokens.TextStyles.title)
                                .foregroundStyle(Theme.foreground)
                        }
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
            // painting over the header above it. In a scroll view `.fit` takes
            // the full width and its own height, so the photo's edges line up
            // with the card's. Zoomable, as in photo detail: a closer look is
            // half of deciding whether to believe a photo.
            RemotePhotoImage(photo: photo, contentMode: .fit, isZoomable: true, onLoad: { loadedImage = $0 })
                // On the photo's own bounds, before the frame widens them.
                .overlay {
                    if let loadedImage {
                        ProofReveal(
                            image: loadedImage,
                            isShown: $isProofShown,
                            download: downloadStatus,
                            onDownload: { Task { await download(photo) } }
                        ) {
                            proof(for: photo)
                        }
                        // The proof is drawn for sighted users only, and
                        // nothing under the photo repeats it any more.
                        .accessibilityValue(proofDescription(for: photo))
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
                .padding(.horizontal, DesignTokens.Space.s6)
                .padding(.top, DesignTokens.Space.s4)

            if let owner, !owner.socialLinks.items.isEmpty {
                socialLinks(owner.socialLinks.items)
                    .padding(.horizontal, DesignTokens.Space.s6)
                    .padding(.top, DesignTokens.Space.s4)
            }
        }
        .padding(.bottom, DesignTokens.Space.s6)
        // Close is the bar's, faded on its own.
        .fadesWhilePhotoZoomed(isPhotoZoomed)
        .photoZoomLayer(isZoomed: $isPhotoZoomed, cornerRadius: DesignTokens.Radius.lg, viewport: viewport) {
            isProofShown.toggle()
        }
    }

    /// The owner's handles, as chips. Who took the photo, their verified
    /// name and when are on the photo itself, a tap away.
    private func socialLinks(_ links: [SocialLink]) -> some View {
        // Wraps rather than scrolls: five handles at most, and a horizontal
        // scroller inside a full-screen cover competes with the dismiss
        // gesture.
        FlowLayout(spacing: DesignTokens.Space.s2) {
            ForEach(links) { link in
                socialChip(link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the proof over the photo says: the website's username and date,
    /// with the verified name between them when the owner publishes one.
    @ViewBuilder
    private func proof(for photo: VerifiedPhoto) -> some View {
        if let owner {
            Text(verbatim: "@\(owner.username)")
            if let identity = owner.verifiedIdentity {
                Text(identity.displayName)
            }
        }
        Text(Self.capturedDate(photo.capturedAt))
    }

    private static func capturedDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).day().year())
    }

    /// `proof(for:)` as one line, for VoiceOver.
    private func proofDescription(for photo: VerifiedPhoto) -> String {
        let captured = "captured \(Self.capturedDate(photo.capturedAt))"
        guard let owner else { return captured }
        let by = owner.isVerified ? "Verified by @\(owner.username)" : "@\(owner.username)"
        if let identity = owner.verifiedIdentity {
            return "\(by), \(identity.displayName), \(captured)"
        }
        return "\(by), \(captured)"
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

    /// Saves the photo to Photos as it's stored: the file the website's
    /// download serves, downloaded again rather than re-encoded from what's
    /// on screen. Photos keeps its pixels byte for byte, mark included, but
    /// strips the C2PA manifest on import, so the library copy can't be
    /// verified. The link still can.
    private func download(_ photo: VerifiedPhoto) async {
        guard downloadStatus == .ready else { return }
        downloadStatus = .downloading
        do {
            let data = try await PhotoRepository.downloadImage(path: photo.storagePath)
            try await PhotoLibrarySaver.save(imageData: data)
        } catch PhotoLibrarySaverError.accessDenied {
            downloadStatus = .ready
            downloadError = "Allow the human internet to add photos in Settings, then try again."
            return
        } catch {
            Log.photos.error("Verification-view download failed for \(photo.id, privacy: .public): \(error, privacy: .public)")
            downloadStatus = .ready
            downloadError = "Please try again."
            return
        }
        downloadStatus = .saved
        AccessibilityNotification.Announcement("Saved to Photos.").post()
        try? await Task.sleep(for: .seconds(1.6))
        downloadStatus = .ready
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
