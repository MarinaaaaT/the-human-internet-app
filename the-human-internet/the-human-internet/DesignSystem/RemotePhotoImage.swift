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
    let storagePath: String
    var contentMode: ContentMode = .fill

    @State private var imageData: Data?
    @State private var didFail = false

    var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
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
        .task(id: storagePath) {
            guard imageData == nil else { return }
            do {
                imageData = try await PhotoRepository.downloadImage(path: storagePath)
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
