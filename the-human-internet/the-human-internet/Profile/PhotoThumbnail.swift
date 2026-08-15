//
//  PhotoThumbnail.swift
//  the-human-internet
//

import SwiftUI

struct PhotoThumbnail: View {
    /// `.inactive` is the grid's normal state — no indicator at all. The
    /// other two only appear while `ProfileView` is in selection mode.
    enum SelectionState {
        case inactive, unselected, selected
    }

    let photo: VerifiedPhoto
    var selectionState: SelectionState = .inactive

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
            .overlay {
                if selectionState == .selected {
                    Color.black.opacity(0.25)
                }
            }
            .clipped()
            // Top-trailing, because bottom-trailing is already the
            // upload-status badge's corner.
            .overlay(alignment: .topTrailing) {
                selectionIndicator
            }
            .overlay(alignment: .bottomTrailing) {
                statusBadge
            }
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        switch selectionState {
        case .inactive:
            EmptyView()
        case .unselected:
            Image(systemName: "circle")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                // Backing disc so the outline stays visible on a light photo,
                // same trick the status badge below uses.
                .background(.black.opacity(0.35), in: Circle())
                .padding(8)
        case .selected:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Theme.accentBlue)
                .padding(8)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if appState.processingPhotoIDs.contains(photo.id) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.7)
                .padding(6)
                .background(.black.opacity(0.45), in: Circle())
                .padding(6)
        } else if appState.failedPhotoIDs.contains(photo.id) {
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
