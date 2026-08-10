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
            .aspectRatio(1, contentMode: .fill)
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
