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

    private struct ShareOption: Identifiable {
        enum Kind {
            case copyLink
            /// Not yet wired to a real platform integration.
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
                                dismiss()
                            }
                        } label: {
                            optionLabel(for: option)
                        }
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
