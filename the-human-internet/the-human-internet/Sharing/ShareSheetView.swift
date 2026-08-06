//
//  ShareSheetView.swift
//  the-human-internet
//

import SwiftUI

struct ShareSheetView: View {
    let photo: VerifiedPhoto
    @Environment(\.dismiss) private var dismiss

    private struct ShareOption: Identifiable {
        let id = UUID()
        let symbol: String
        let label: String
    }

    private let options: [ShareOption] = [
        ShareOption(symbol: "link", label: "Copy Link"),
        ShareOption(symbol: "camera.aperture", label: "Instagram"),
        ShareOption(symbol: "music.note", label: "TikTok"),
        ShareOption(symbol: "person.2.fill", label: "Facebook"),
        ShareOption(symbol: "message.fill", label: "Messages")
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
                            dismiss()
                        } label: {
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
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ShareSheetView(photo: VerifiedPhoto(id: UUID(), userID: UUID(), storagePath: "preview/example.jpg", capturedAt: .now, verificationDeepLink: "thehumaninternet://photo/preview"))
    }
}
