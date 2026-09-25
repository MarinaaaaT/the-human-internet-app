//
//  PhotoWatermarker.swift
//  the-human-internet
//

import SwiftUI
import UIKit

enum PhotoWatermarkerError: Error {
    case invalidImage
    /// The `BrandMarkWatermark` image set is missing from the bundle.
    case markMissing
    case encodeFailed
}

/// Burns the brand mark into a captured JPEG's actual pixels, so the mark
/// travels with the photo wherever it's uploaded, shared, or downloaded.
/// Deliberately not applied to the copy saved to the user's own device
/// Photos library, which stays an untouched copy of exactly what they shot.
///
/// **No longer the main path.** With `server_side_watermark` on, the signing
/// Lambda burns the mark in (`aws-signing-lambda/src/watermark.rs` in the
/// backend repo) so the capture can be signed first and kept as the
/// watermarked photo's C2PA ingredient. This stays for the flag-off path and
/// for the developer tools' Skip C2PA.
///
/// **The mark is an image**, the `BrandMarkWatermark` image set — the same
/// PNG as the Lambda's `assets/brand-mark.png`. All three renderings (this,
/// the Lambda's, and `ProvisionalWatermark`'s overlay) draw that artwork at
/// `markRect`, so they match pixel for pixel in placement; the overlay is
/// what a photo looks like until the real one replaces it. To change the
/// artwork, replace the PNG in both repos — nothing else.
enum PhotoWatermarker {
    /// Asset catalog name of the artwork.
    static let markAssetName = "BrandMarkWatermark"
    /// Mark width, and its inset from the top and trailing edges, as
    /// fractions of the image's shorter side. Mirrored by the Lambda's
    /// `MARK_SIZE_FRACTION` / `MARK_PADDING_FRACTION`. The height follows
    /// from the artwork's own aspect ratio.
    static let markSizeFraction: CGFloat = 0.09
    static let markPaddingFraction: CGFloat = 0.035

    /// Where the mark goes on an image of `imageSize`, for artwork whose
    /// height/width is `markAspectRatio`: top-trailing, inset.
    static func markRect(in imageSize: CGSize, markAspectRatio: CGFloat) -> CGRect {
        let shorter = min(imageSize.width, imageSize.height)
        let width = shorter * markSizeFraction
        let padding = shorter * markPaddingFraction
        return CGRect(x: imageSize.width - width - padding, y: padding, width: width, height: width * markAspectRatio)
    }

    /// Composites off the main actor — real work at full photo resolution.
    static func watermark(imageData: Data) async throws -> Data {
        guard let baseImage = UIImage(data: imageData) else {
            throw PhotoWatermarkerError.invalidImage
        }
        guard let markImage = UIImage(named: markAssetName), markImage.size.width > 0 else {
            throw PhotoWatermarkerError.markMissing
        }

        return try await Task.detached(priority: .userInitiated) {
            let markRect = PhotoWatermarker.markRect(
                in: baseImage.size,
                markAspectRatio: markImage.size.height / markImage.size.width
            )

            let format = UIGraphicsImageRendererFormat()
            format.scale = baseImage.scale
            let output = UIGraphicsImageRenderer(size: baseImage.size, format: format).image { _ in
                baseImage.draw(in: CGRect(origin: .zero, size: baseImage.size))
                markImage.draw(in: markRect)
            }

            guard let jpegData = output.jpegData(compressionQuality: 0.95) else {
                throw PhotoWatermarkerError.encodeFailed
            }
            return jpegData
        }.value
    }
}
