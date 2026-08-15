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
struct PhotoVerificationView: View {
    let photoID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var photo: VerifiedPhoto?
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

            Spacer()
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
    }
}

#Preview {
    Color.clear.fullScreenCover(isPresented: .constant(true)) {
        PhotoVerificationView(photoID: UUID())
    }
}
