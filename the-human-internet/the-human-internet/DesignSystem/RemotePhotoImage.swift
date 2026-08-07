//
//  RemotePhotoImage.swift
//  the-human-internet
//

import SwiftUI
import UIKit

/// Downloads and renders a photo from the private `photos` Storage bucket.
/// Shared by every view that displays a stored photo (thumbnails, detail,
/// verification) so the download/placeholder/failure states live in one place.
struct RemotePhotoImage: View {
    let photo: VerifiedPhoto
    var contentMode: ContentMode = .fill

    @State private var imageData: Data?
    @State private var didFail = false
    /// Which photo `imageData` actually belongs to. Call sites that reuse
    /// one spot in the view tree for different photos over time — like
    /// CameraCaptureView's last-photo thumbnail, which isn't in a ForEach —
    /// keep this view's `@State` alive across a photo change, so the bytes
    /// have to be matched against the current photo explicitly rather than
    /// assumed fresh.
    @State private var loadedPath: String?

    private var isLoaded: Bool { loadedPath == photo.storagePath }

    var body: some View {
        Group {
            if isLoaded, let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if didFail {
                placeholder {
                    Image(systemName: "photo")
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                placeholder {
                    ProgressView().tint(.white)
                }
            }
        }
        .task(id: photo.storagePath) {
            // Guards on the *photo*, not merely on "have I loaded
            // something" — the latter left a reused view showing the
            // previous photo forever.
            guard !isLoaded else { return }
            imageData = nil
            didFail = false

            // A photo that's still uploading (or just resumed after a
            // force-quit) has no object in Storage yet — fetching it there
            // would 404 and, since this task only runs once per storagePath,
            // never retry even after the upload finishes moments later. The
            // local pending copy has the identical bytes, so prefer it.
            if let localData = PhotoUploadQueue.localImageData(for: photo.id) {
                imageData = localData
                loadedPath = photo.storagePath
                return
            }
            do {
                imageData = try await PhotoRepository.downloadImage(path: photo.storagePath)
                loadedPath = photo.storagePath
            } catch {
                didFail = true
                debugPrint(error)
            }
        }
    }

    /// A bare `Color` expands greedily, so in a `.fit` context the placeholder
    /// would swallow all available height while downloading and then snap when
    /// the real image arrives. Reserving a portrait aspect keeps layout stable.
    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Theme.surface
            content()
        }
        .aspectRatio(contentMode == .fit ? 3.0 / 4.0 : nil, contentMode: contentMode)
    }
}
