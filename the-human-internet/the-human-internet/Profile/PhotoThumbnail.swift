//
//  PhotoThumbnail.swift
//  the-human-internet
//

import SwiftUI

struct PhotoThumbnail: View {
    let photo: VerifiedPhoto

    @Environment(AppState.self) private var appState

    var body: some View {
        RemotePhotoImage(photo: photo)
            // `.fit`, not `.fill`: in a LazyVGrid, the proposed height is
            // effectively unconstrained, and "fill a 1:1 box that's at
            // least as tall as infinity" is undefined — it silently fell
            // through to each photo's own aspect ratio instead of a square.
            // `.fit` against (width, ∞) unambiguously resolves to a
            // (width, width) square; the inner `RemotePhotoImage` still
            // fills *that* square and gets clipped to it below.
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                statusBadge
            }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if appState.uploadingPhotoIDs.contains(photo.id) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.7)
                .padding(6)
                .background(.black.opacity(0.45), in: Circle())
                .padding(6)
        } else if appState.failedUploadIDs.contains(photo.id) {
            Button {
                PhotoUploadQueue.retry(photoID: photo.id, appState: appState)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.red, in: Circle())
            }
            .padding(6)
        }
    }
}

#Preview {
    PhotoThumbnail(photo: VerifiedPhoto(id: UUID(), userID: UUID(), storagePath: "preview/example.jpg", capturedAt: .now, verificationDeepLink: "thehumaninternet://photo/preview", shortCode: "preview1"))
        .frame(width: 120, height: 120)
        .environment(AppState())
}
