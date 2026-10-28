//
//  RemotePhotoImage.swift
//  the-human-internet
//

import SwiftUI
import UIKit
import ImageIO

/// Renders a stored photo — from this device when it has a copy, otherwise
/// downloaded from the private `photos` Storage bucket. Shared by every view
/// that displays a stored photo (thumbnails, detail, verification) so the
/// download/placeholder/failure states live in one place.
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
    /// The photo's only copy is still the raw capture, with no watermark in
    /// its pixels yet (`AppState.provisionalPhotoIDs`). Draws
    /// `ProvisionalWatermark` over it, and when this flips to `false` the
    /// view reloads to pick up the real watermarked bytes. Passed in rather
    /// than read from `AppState`, like the rest of this view's inputs.
    var isProvisional: Bool = false
    /// What `ProvisionalWatermark` draws while `isProvisional` —
    /// `AppState.provisionalMarks`.
    var provisionalMarks: ProvisionalWatermark.Marks = .fingerprint
    /// Pinch or double-tap to zoom, for a `.fit` photo shown on its own
    /// (photo detail and the in-app verification page). Only inside a
    /// `photoZoomLayer`, which draws the photo so it can grow across the
    /// whole screen; this view then just holds its place. Turning it off
    /// drops the zoom back to 1x — photo detail's pager turns it off for
    /// every page but the open one, so a photo swiped away isn't still
    /// zoomed when swiped back to.
    ///
    /// Also what earns the real pixels: only a zoomable photo is decoded at
    /// full resolution (see `Resolution`).
    var isZoomable: Bool = false
    /// Reads the photo from `LocalPhotoStore` when this device has it, and
    /// keeps a copy of anything it does have to download — so the user's own
    /// photos in the Profile grid and photo detail open without waiting on
    /// the network. The verification page leaves it off: it shows what
    /// everyone else is shown, so it always loads from Storage.
    var usesLocalCopy: Bool = false
    /// Handed each image as it loads, for a caller that draws something of
    /// its own from the same pixels — the verification page's frosted proof
    /// blurs it.
    var onLoad: ((UIImage) -> Void)? = nil

    @Environment(\.isInPhotoZoomLayer) private var isInPhotoZoomLayer
    @State private var image: UIImage?
    /// Black or white for the provisional mark over `image` — worked out once
    /// per loaded image rather than on every body evaluation.
    @State private var provisionalMarkColor: PhotoWatermarker.MarkColor = .white
    @State private var didFail = false
    /// Which photo — and which version of it — `image` actually belongs to.
    /// Call sites that reuse one spot in the view tree for different photos
    /// over time — like CameraCaptureView's last-photo thumbnail, which isn't
    /// in a ForEach — keep this view's `@State` alive across a photo change,
    /// so the bytes have to be matched against the current photo explicitly
    /// rather than assumed fresh. The provisional flag is part of it so the
    /// raw capture is replaced the moment the watermarked photo exists.
    @State private var loadedKey: String?
    /// How detailed `image` is. Only ever goes up for the same photo: a
    /// photo that's had its full decode keeps it until the view goes away.
    @State private var loadedResolution: Resolution?

    private var loadKey: String { "\(photo.storagePath)#\(isProvisional ? "raw" : "final")" }
    private var isLoaded: Bool { loadedKey == loadKey }

    /// How much of the photo to decode.
    ///
    /// Photo detail's pager is why there's a middle step. Every page beside
    /// the open one used to hold a full 12MP decode (~48MB), and each had to
    /// go up to the GPU as it slid on screen, mid-swipe — which is what made
    /// paging stutter. Now they decode to `screen`, a quarter of the pixels
    /// and still more than a phone shows at 1x, and only the open page — the
    /// one that can zoom — swaps up to `full`, once it's settled. The swap
    /// keeps the screen-sized image up until the full one is ready, so
    /// nothing flashes.
    enum Resolution: Int, Comparable {
        /// Capped at `thumbnailMaxPixelSize`.
        case thumbnail
        /// Capped at `screenMaxPixelSize`.
        case screen
        /// Every pixel, for zooming in up to 4x.
        case full

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        var maxPixelSize: CGFloat? {
            switch self {
            case .thumbnail: return RemotePhotoImage.thumbnailMaxPixelSize
            case .screen: return RemotePhotoImage.screenMaxPixelSize
            case .full: return nil
            }
        }
    }

    private var resolution: Resolution {
        if isThumbnail { return .thumbnail }
        return isZoomable ? .full : .screen
    }

    /// A 2-column grid renders each cell at well under this on any device
    /// size, so decoding to this cap loses no visible detail while using a
    /// fraction of the memory/bandwidth of a ~4000px full-resolution capture.
    nonisolated static let thumbnailMaxPixelSize: CGFloat = 600
    /// The long side of a photo shown full width, unzoomed, on the largest
    /// iPhone is under 1,600px for a 3:4 capture, so this is sharp on all of
    /// them.
    nonisolated static let screenMaxPixelSize: CGFloat = 2048

    var body: some View {
        Group {
            if isLoaded, let image {
                if isZoomable, isInPhotoZoomLayer {
                    // Sized to the photo's own shape, as the image alone
                    // would be, so the layer's photo rests exactly here and
                    // turning zoom on or off moves nothing.
                    Color.clear
                        .aspectRatio(image.size, contentMode: contentMode)
                        .anchorPreference(key: ZoomablePhotoPreferenceKey.self, value: .bounds) {
                            ZoomablePhoto(image: image, isProvisional: isProvisional, marks: provisionalMarks, markColor: provisionalMarkColor, restingBounds: $0)
                        }
                } else {
                    LoadedPhoto(image: image, contentMode: contentMode, isProvisional: isProvisional, marks: provisionalMarks, markColor: provisionalMarkColor)
                }
            } else if didFail {
                placeholder {
                    Image(systemName: "photo")
                        .foregroundStyle(Theme.mutedForeground)
                }
            } else {
                placeholder {
                    ProgressView().tint(Theme.foreground)
                }
            }
        }
        .task(id: "\(loadKey)@\(resolution.rawValue)") {
            // Guards on the *photo*, not merely on "have I loaded
            // something" — the latter left a reused view showing the
            // previous photo forever.
            let wanted = resolution
            if isLoaded {
                guard let loadedResolution, loadedResolution < wanted else { return }
                // A more detailed decode of the photo already on screen:
                // it stays up meanwhile.
            } else {
                image = nil
                didFail = false
            }

            // The cache only ever holds final (watermarked) images — see
            // `cacheAndSet` — so a provisional load always goes to disk.
            if isThumbnail, !isProvisional, let cached = PhotoThumbnailCache.image(for: photo.storagePath) {
                image = cached
                loadedKey = loadKey
                loadedResolution = .thumbnail
                onLoad?(cached)
                return
            }

            // Pinned before the first `await`: if the photo turns final
            // while this load is decoding the raw capture, a new load starts
            // under the new key, and this one's result must not land there.
            let key = loadKey
            let photoID = photo.id
            let userID = photo.userID
            let maxPixelSize = wanted.maxPixelSize

            // A photo that's still uploading (or just resumed after a
            // force-quit) has no object in Storage yet — fetching it there
            // would 404 and, since this task only runs once per storagePath,
            // never retry even after the upload finishes moments later. The
            // local pending copy has the identical bytes, so prefer it.
            if let localData = PhotoUploadQueue.localImageData(for: photoID) {
                cacheAndSet(await Self.decoded({ localData }, maxPixelSize: maxPixelSize), for: key, at: wanted)
                return
            }
            if usesLocalCopy,
               let stored = await Self.decoded({ LocalPhotoStore.data(photoID: photoID, userID: userID) }, maxPixelSize: maxPixelSize) {
                cacheAndSet(stored, for: key, at: wanted)
                return
            }
            do {
                let data = try await PhotoRepository.downloadImage(path: photo.storagePath)
                if usesLocalCopy, !Task.isCancelled {
                    LocalPhotoStore.store(data, photoID: photoID, userID: userID)
                }
                cacheAndSet(await Self.decoded({ data }, maxPixelSize: maxPixelSize), for: key, at: wanted)
            } catch {
                // Superseded or torn down, not failed — and an upgrade that
                // fails still has the photo it started from on screen.
                guard !Task.isCancelled, !isLoaded else { return }
                didFail = true
                Log.photos.error("Download failed for \(photo.storagePath, privacy: .public): \(error, privacy: .public)")
            }
        }
    }

    /// Never caches a raw capture: the cache is keyed by storage path alone,
    /// so a cached raw frame would outlive the watermarked photo replacing it
    /// and be shown, unmarked, for as long as the process lives.
    ///
    /// Drops `decoded` if `key` is no longer the current load — a newer one
    /// superseded it while it decoded — or if it's less detailed than what's
    /// already on screen, as a screen-sized decode finishing after the full
    /// one would be.
    private func cacheAndSet(_ decoded: UIImage?, for key: String, at resolution: Resolution) {
        guard key == loadKey else { return }
        if isLoaded, let loadedResolution, resolution < loadedResolution { return }
        if isProvisional, let decoded, let mark = UIImage(named: PhotoWatermarker.markAssetName), mark.size.width > 0 {
            let rect = PhotoWatermarker.markRect(in: decoded.size, markAspectRatio: mark.size.height / mark.size.width)
            provisionalMarkColor = PhotoWatermarker.markColor(for: decoded, in: rect)
        }
        image = decoded
        loadedKey = key
        loadedResolution = resolution
        if let decoded { onLoad?(decoded) }
        if isThumbnail, !isProvisional, let decoded {
            PhotoThumbnailCache.store(decoded, for: photo.storagePath)
        }
    }

    /// Reads and decodes off the main thread. With photos coming off disk, a
    /// whole screen of grid cells loads at once, and decoding them there
    /// would stall scrolling.
    private static func decoded(_ read: @escaping @Sendable () -> Data?, maxPixelSize: CGFloat?) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            read().flatMap { decode($0, maxPixelSize: maxPixelSize) }
        }.value
    }

    /// `nil` decodes every pixel.
    nonisolated private static func decode(_ data: Data, maxPixelSize: CGFloat?) -> UIImage? {
        guard let maxPixelSize else {
            // Decoded now rather than on first draw, which is on the main thread.
            let image = UIImage(data: data)
            return image?.preparingForDisplay() ?? image
        }
        return downsampled(data: data, maxPixelSize: maxPixelSize) ?? UIImage(data: data)
    }

    /// Decodes straight to a capped pixel size via ImageIO instead of
    /// decoding the full-resolution bitmap and scaling it down afterward —
    /// the whole point is to never materialize the full-size decode.
    nonisolated private static func downsampled(data: Data, maxPixelSize: CGFloat) -> UIImage? {
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

/// A loaded photo as `RemotePhotoImage` draws it — or, for a zoomable one,
/// as its `photoZoomLayer` does — with the provisional mark over it until
/// its own is burned in.
struct LoadedPhoto: View {
    let image: UIImage
    var contentMode: ContentMode = .fit
    let isProvisional: Bool
    var marks: ProvisionalWatermark.Marks = .fingerprint
    let markColor: PhotoWatermarker.MarkColor

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: contentMode)
            // On the image itself, before any caller's clipping, so the mark
            // is placed against the whole photo even where a `.fill`
            // thumbnail crops it — and zooms along with the photo.
            .overlay {
                if isProvisional { ProvisionalWatermark(color: markColor, marks: marks) }
            }
    }
}

/// Process-wide store of decoded grid thumbnails, keyed by storage path.
///
/// Split out of `RemotePhotoImage` rather than left as a static on the view
/// so sign-out has something to call that isn't a SwiftUI view type, and so
/// the eviction contract has one documented home.
enum PhotoThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for storagePath: String) -> UIImage? {
        cache.object(forKey: storagePath as NSString)
    }

    static func store(_ image: UIImage, for storagePath: String) {
        cache.setObject(image, forKey: storagePath as NSString)
    }

    /// Dropped on sign-out for the same reason `PhotoUploadQueue.pruneOnSignOut`
    /// deletes pending files: the next person on a shared device shouldn't be
    /// able to surface the previous user's photos, and decoded thumbnails held
    /// in a process-wide cache are the same exposure as bytes left on disk —
    /// storage paths are namespaced per user, so nothing here is ever reusable
    /// across an account change anyway.
    ///
    /// Note this is the only *deliberate* eviction. `NSCache` also drops
    /// entries on its own under memory pressure, which is why the grid's
    /// guarantee is "downloaded once per photo per launch, absent memory
    /// pressure" rather than a hard once.
    static func removeAll() {
        cache.removeAllObjects()
    }
}
