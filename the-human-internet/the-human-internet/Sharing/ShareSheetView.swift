//
//  ShareSheetView.swift
//  the-human-internet
//

import SwiftUI
import UIKit

struct ShareSheetView: View {
    let photo: VerifiedPhoto
    @Environment(\.openURL) private var openURL
    @State private var didCopy = false

    @State private var showInstructions = false
    /// Set when "Continue" is tapped in the instructions sheet; acted on
    /// only once that sheet has actually finished dismissing (see its
    /// `onDismiss`) — presenting a new sheet in the same beat as dismissing
    /// another is unreliable.
    @State private var pendingShare = false
    @State private var showActivitySheet = false
    @State private var showMessageCompose = false
    /// A temp file, not an in-memory `UIImage` — Instagram/X/TikTok's share
    /// extensions run in a separate, memory-constrained process, and
    /// crashed (or, for TikTok, failed with a generic error) when handed a
    /// full-resolution `UIImage` to transfer in-memory. A file URL lets the
    /// extension read/stream the bytes itself instead.
    @State private var shareFileURL: URL?
    @State private var isPreparingShare = false
    @State private var shareError: String?

    private struct ShareOption: Identifiable {
        enum Kind {
            /// Shows the pre-share instructions, then the native share
            /// sheet with just the photo — see `beginPlatformShare` for why
            /// most platform icons share this one path.
            case platform
            /// The in-app Messages composer, which takes the photo *and*
            /// the link as body text — see `beginMessagesShare`.
            case messages
            /// The platform's own composer, opened pre-filled with the
            /// link — see `ShareIntent`. No image changes hands: the Open
            /// Graph card supplies the picture, and survives the trip in a
            /// way an uploaded JPEG's C2PA manifest does not.
            case linkIntent(ShareIntent)
        }

        let id: String
        let kind: Kind
        let symbol: String
        let label: String
    }

    private let options: [ShareOption] = [
        ShareOption(id: "instagram", kind: .platform, symbol: "camera.aperture", label: "Instagram"),
        ShareOption(id: "reddit", kind: .linkIntent(.reddit), symbol: "bubble.left.and.bubble.right.fill", label: "Reddit"),
        ShareOption(id: "x", kind: .linkIntent(.x), symbol: "xmark", label: "X"),
        ShareOption(id: "facebook", kind: .platform, symbol: "person.2.fill", label: "Facebook"),
        ShareOption(id: "messages", kind: .messages, symbol: "message.fill", label: "Messages")
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                SheetGrabber()
                    .padding(.top, 8)

                Text("Share your human photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 20) {
                    ForEach(options) { option in
                        Button {
                            switch option.kind {
                            case .platform:
                                beginPlatformShare()
                            case .messages:
                                beginMessagesShare()
                            case .linkIntent(let intent):
                                beginLinkIntentShare(intent)
                            }
                        } label: {
                            optionLabel(for: option)
                        }
                        .disabled(isPreparingShare)
                    }
                }
                .overlay {
                    if isPreparingShare {
                        ProgressView().tint(.white)
                    }
                }

                copyLinkRow

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .presentationDetents([.fraction(0.4)])
        .presentationBackground(Theme.background)
        .sheet(isPresented: $showInstructions, onDismiss: {
            guard pendingShare else { return }
            pendingShare = false
            Task { await prepareAndPresentActivitySheet() }
        }) {
            ShareInstructionsSheetView {
                pendingShare = true
                showInstructions = false
            }
        }
        // A plain, standard photo share — just the image, like sharing from
        // Photos. No platform reliably accepts caption text handed to it
        // this way (Facebook and Instagram never do, by platform policy),
        // which is what `ShareInstructionsSheetView` already told the user:
        // the link is on their clipboard to paste in themselves.
        .background(
            ActivityView(
                isPresented: $showActivitySheet,
                activityItems: shareFileURL.map { [$0] } ?? [],
                excludedActivityTypes: [.assignToContact, .addToReadingList, .openInIBooks, .print],
                onComplete: cleanUpShareFile
            )
        )
        .background(
            MessageComposeView(isPresented: $showMessageCompose, body: messageBody)
        )
        .alert(
            "Couldn't prepare photo",
            isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })
        ) {
            Button("OK") { shareError = nil }
        } message: {
            Text(shareError ?? "Please try again.")
        }
    }

    /// The link, doubling as its own copy button — tapping the text or the
    /// icon copies. Replaces the old "Copy Link" icon in the row above: it
    /// sat among the platform icons as though it were another destination,
    /// and the link it copied was already displayed right underneath.
    private var copyLinkRow: some View {
        Button(action: copyLink) {
            HStack(spacing: 8) {
                Text(photo.verificationLink)
                    .font(.system(size: 12, design: .monospaced))
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(didCopy ? Theme.success : Theme.textSecondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy verification link")
    }

    /// The one place a caption is actually pre-filled, because Messages is
    /// the one destination that accepts body text from a third-party app.
    ///
    /// First person, unlike the other destinations' wording: a text goes to
    /// someone who already knows you, so "a real human" reads oddly formal
    /// there.
    private var messageBody: String {
        "Proof I took this photo: \(photo.verificationURL.absoluteString)"
    }

    /// Copies the verification link immediately — before the instructions
    /// sheet even finishes animating in — so it's already on the clipboard
    /// by the time the user reads "paste it into your caption."
    private func beginPlatformShare() {
        UIPasteboard.general.url = photo.verificationURL
        showInstructions = true
    }

    /// Straight to the Messages composer: no clipboard hand-off and no
    /// instructions sheet, since there's nothing for the user to paste.
    ///
    /// Nothing to prepare either — the message is the link, so unlike the
    /// share-sheet path this doesn't download the photo or write a temp
    /// file, and opens immediately.
    private func beginMessagesShare() {
        guard MessageComposeView.canSendText else {
            // Simulator, or hardware with no Messages account — fall back
            // to the path every other icon takes.
            beginPlatformShare()
            return
        }

        showMessageCompose = true
    }

    /// Hands the link straight to the platform's own composer. No
    /// clipboard hand-off, no instructions sheet and no image: the link is
    /// already in the post, and the card renders the photo from it.
    private func beginLinkIntentShare(_ intent: ShareIntent) {
        guard let webURL = intent.composerURL(for: photo) else {
            beginPlatformShare()
            return
        }

        // The app's own scheme first — an https intent doesn't reliably
        // hand off to the app, and X explicitly redirects its web intent
        // out to the browser, landing the user somewhere they're usually
        // not signed in. See `ShareIntent.appURL`.
        guard let appURL = intent.appURL(for: photo) else {
            open(webURL)
            return
        }

        openURL(appURL) { openedInApp in
            // False when the app isn't installed, which is the ordinary
            // case rather than an error — fall through to the web composer.
            if !openedInApp { open(webURL) }
        }
    }

    /// Opens a share destination, falling back to the generic share sheet
    /// if nothing on the device can handle it at all.
    private func open(_ url: URL) {
        openURL(url) { accepted in
            // Only an unusual configuration can fail to open an https URL
            // (every browser removed, or a restrictions profile). Fall
            // back rather than leaving the tap dead.
            if !accepted { beginPlatformShare() }
        }
    }

    /// Downloads the photo's bytes — or reads the local pending copy if it
    /// hasn't finished uploading yet — and writes them to a temp file for
    /// whichever presenter is about to take over. Returns `false` if that
    /// failed, having already surfaced the error.
    private func prepareShareFile() async -> Bool {
        isPreparingShare = true
        defer { isPreparingShare = false }
        do {
            let data = try await imageData()
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            try data.write(to: fileURL, options: .atomic)
            shareFileURL = fileURL
            return true
        } catch {
            shareError = "Please try again."
            Log.sharing.error("Preparing share file failed: \(error, privacy: .public)")
            return false
        }
    }

    /// Hands the prepared file's URL alone to the native share sheet.
    private func prepareAndPresentActivitySheet() async {
        guard await prepareShareFile() else { return }
        showActivitySheet = true
    }

    private func imageData() async throws -> Data {
        if let local = PhotoUploadQueue.localImageData(for: photo.id) {
            return local
        }
        return try await PhotoRepository.downloadImage(path: photo.storagePath)
    }

    private func cleanUpShareFile() {
        if let shareFileURL {
            try? FileManager.default.removeItem(at: shareFileURL)
        }
        shareFileURL = nil
    }

    private func optionLabel(for option: ShareOption) -> some View {
        VStack(spacing: 6) {
            Image(systemName: option.symbol)
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.surface)
                .clipShape(Circle())
            Text(option.label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Copies the public web link — the one anybody can open, signed out —
    /// rather than the `thehumaninternet://` deep link, which only resolves
    /// for people who already have the app.
    ///
    /// Deliberately doesn't dismiss the sheet: copying is no longer the
    /// headline action, so pulling the sheet away would cut off someone who
    /// grabbed the link and still wants to pick a destination.
    private func copyLink() {
        UIPasteboard.general.url = photo.verificationURL
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        withAnimation(.easeOut(duration: 0.15)) { didCopy = true }

        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.15)) { didCopy = false }
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ShareSheetView(photo: VerifiedPhoto(id: UUID(), userID: UUID(), storagePath: "preview/example.jpg", capturedAt: .now, verificationDeepLink: "thehumaninternet://photo/preview", shortCode: "preview1"))
    }
}
