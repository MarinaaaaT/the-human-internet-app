//
//  RemotePhotoImage.swift
//  the-human-internet
//

import SwiftUI
import UIKit
import ImageIO

/// Downloads and renders a photo from the private `photos` Storage bucket.
/// Shared by every view that displays a stored photo (thumbnails, detail,
/// verification) so the download/placeholder/failure states live in one place.
struct RemotePhotoImage: View {
    let photo: VerifiedPhoto
    var contentMode: ContentMode = .fill
    /// Grid thumbnails opt into a shared, downsampled cache. A `LazyVGrid`
    /// recreates each cell's view identity as it scrolls out and back in, so
    /// without a cache keyed by storage path, re-scrolling a 50-photo grid
    /// redownloaded and re-decoded every photo at full resolution on every
    /// pass. Full-resolution contexts (photo detail, verification) don't
    /// participate — they're single, long-lived view instances that don't
    /// get torn down on scroll, so there's nothing to cache, and they need
    /// the real resolution.
    var isThumbnail: Bool = false

    @State private var image: UIImage?
    @State private var didFail = false
    /// Which photo `image` actually belongs to. Call sites that reuse
    /// one spot in the view tree for different photos over time — like
    /// CameraCaptureView's last-photo thumbnail, which isn't in a ForEach —
    /// keep this view's `@State` alive across a photo change, so the bytes
    /// have to be matched against the current photo explicitly rather than
    /// assumed fresh.
    @State private var loadedPath: String?

    private var isLoaded: Bool { loadedPath == photo.storagePath }

    /// A 2-column grid renders each cell at well under this on any device
    /// size, so decoding to this cap loses no visible detail while using a
    /// fraction of the memory/bandwidth of a ~4000px full-resolution capture.
    private static let thumbnailMaxPixelSize: CGFloat = 600
    private static let thumbnailCache = NSCache<NSString, UIImage>()

    var body: some View {
        Group {
            if isLoaded, let image {
                Image(uiImage: image)
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
            image = nil
            didFail = false

            if isThumbnail, let cached = Self.thumbnailCache.object(forKey: photo.storagePath as NSString) {
                image = cached
                loadedPath = photo.storagePath
                return
            }

            // A photo that's still uploading (or just resumed after a
            // force-quit) has no object in Storage yet — fetching it there
            // would 404 and, since this task only runs once per storagePath,
            // never retry even after the upload finishes moments later. The
            // local pending copy has the identical bytes, so prefer it.
            if let localData = PhotoUploadQueue.localImageData(for: photo.id) {
                cacheAndSet(decode(localData))
                return
            }
            do {
                let data = try await PhotoRepository.downloadImage(path: photo.storagePath)
                cacheAndSet(decode(data))
            } catch {
                didFail = true
                Log.photos.error("Download failed for \(photo.storagePath, privacy: .public): \(error, privacy: .public)")
            }
        }
    }

    private func cacheAndSet(_ decoded: UIImage?) {
        image = decoded
        loadedPath = photo.storagePath
        if isThumbnail, let decoded {
            Self.thumbnailCache.setObject(decoded, forKey: photo.storagePath as NSString)
        }
    }

    private func decode(_ data: Data) -> UIImage? {
        guard isThumbnail else { return UIImage(data: data) }
        return Self.downsampled(data: data, maxPixelSize: Self.thumbnailMaxPixelSize) ?? UIImage(data: data)
    }

    /// Decodes straight to a capped pixel size via ImageIO instead of
    /// decoding the full-resolution bitmap and scaling it down afterward —
    /// the whole point is to never materialize the full-size decode.
    private static func downsampled(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
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
