//
//  ShareSheetView.swift
//  the-human-internet
//

import SwiftUI
import UIKit

struct ShareSheetView: View {
    let photo: VerifiedPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    @State private var showInstructions = false
    /// Set when "Continue" is tapped in the instructions sheet; acted on
    /// only once that sheet has actually finished dismissing (see its
    /// `onDismiss`) — presenting a new sheet in the same beat as dismissing
    /// another is unreliable.
    @State private var pendingShare = false
    @State private var showActivitySheet = false
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
            case copyLink
            /// Shows the pre-share instructions, then the native share
            /// sheet with just the photo — see `beginPlatformShare` for why
            /// every platform icon shares this one path.
            case platform
        }

        let id: String
        let kind: Kind
        let symbol: String
        let label: String
    }

    private let options: [ShareOption] = [
        ShareOption(id: "copy", kind: .copyLink, symbol: "link", label: "Copy Link"),
        ShareOption(id: "instagram", kind: .platform, symbol: "camera.aperture", label: "Instagram"),
        ShareOption(id: "tiktok", kind: .platform, symbol: "music.note", label: "TikTok"),
        ShareOption(id: "facebook", kind: .platform, symbol: "person.2.fill", label: "Facebook"),
        ShareOption(id: "messages", kind: .platform, symbol: "message.fill", label: "Messages")
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
                            case .copyLink:
                                copyLink()
                            case .platform:
                                beginPlatformShare()
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

                Text(photo.verificationLink)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)

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
        .alert(
            "Couldn't prepare photo",
            isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })
        ) {
            Button("OK") { shareError = nil }
        } message: {
            Text(shareError ?? "Please try again.")
        }
    }

    /// Copies the verification link immediately — before the instructions
    /// sheet even finishes animating in — so it's already on the clipboard
    /// by the time the user reads "paste it into your caption."
    private func beginPlatformShare() {
        UIPasteboard.general.url = photo.verificationURL
        showInstructions = true
    }

    /// Downloads the photo's bytes — or reads the local pending copy if it
    /// hasn't finished uploading yet — writes them to a temp file, and
    /// hands that file's URL alone to the native share sheet.
    private func prepareAndPresentActivitySheet() async {
        isPreparingShare = true
        defer { isPreparingShare = false }
        do {
            let data = try await imageData()
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            try data.write(to: fileURL, options: .atomic)
            shareFileURL = fileURL
            showActivitySheet = true
        } catch {
            shareError = "Please try again."
            debugPrint(error)
        }
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
        let isCopied = option.kind == .copyLink && didCopy
        return VStack(spacing: 6) {
            Image(systemName: isCopied ? "checkmark" : option.symbol)
                .font(.system(size: 20))
                .foregroundStyle(isCopied ? Theme.success : .white)
                .frame(width: 48, height: 48)
                .background(Theme.surface)
                .clipShape(Circle())
            Text(isCopied ? "Copied!" : option.label)
                .font(.system(size: 10))
                .foregroundStyle(isCopied ? Theme.success : Theme.textSecondary)
        }
    }

    /// Copies the public web link — the one anybody can open, signed out —
    /// rather than the `thehumaninternet://` deep link, which only resolves
    /// for people who already have the app.
    private func copyLink() {
        UIPasteboard.general.url = photo.verificationURL
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        withAnimation(.easeOut(duration: 0.15)) { didCopy = true }

        // Held briefly so the confirmation is actually readable before the
        // sheet goes away.
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            dismiss()
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ShareSheetView(photo: VerifiedPhoto(id: UUID(), userID: UUID(), storagePath: "preview/example.jpg", capturedAt: .now, verificationDeepLink: "thehumaninternet://photo/preview"))
    }
}
