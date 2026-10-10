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
/// **The mark is an image**, the `BrandMarkWatermark` image set — the spiral
/// "fingerprint", the same PNG as the Lambda's `assets/brand-mark.png` and
/// Android's `brand_mark_watermark`. Only its alpha is used: it's the mark's
/// shape. All the renderings (this, the Lambda's, and `ProvisionalWatermark`'s
/// overlay) draw it at `markRect`, so they match in placement; the overlay is
/// what a photo looks like until the real one replaces it. To change the
/// artwork, replace the PNG in all three repos — nothing else.
///
/// **The colour adapts to the photo**: solid black on a light background,
/// solid white on a dark one, like the tab bar's glyphs over the live camera.
/// `markColor(for:in:)` decides, by the rule the Lambda's `mark_color` and
/// Android's `PhotoWatermarker` share: sample a 32×32 grid of points across
/// the mark's box, average their Rec. 709 luma (0–1), black above 0.5.
enum PhotoWatermarker {
    /// Asset catalog name of the artwork.
    static let markAssetName = "BrandMarkWatermark"
    /// Mark width, and its inset from the top and trailing edges, as
    /// fractions of the image's shorter side. Mirrored by the Lambda's
    /// `MARK_SIZE_FRACTION` / `MARK_PADDING_FRACTION`. The height follows
    /// from the artwork's own aspect ratio.
    static let markSizeFraction: CGFloat = 0.09
    static let markPaddingFraction: CGFloat = 0.035
    /// Sample points per side of the grid `markColor` averages. Mirrors the
    /// Lambda's `COLOR_SAMPLE_GRID`.
    static let colorSampleGrid = 32
    /// Mean luma above which the background counts as light, and the mark is
    /// black. Mirrors the Lambda's `LIGHT_BACKGROUND_LUMA`.
    static let lightBackgroundLuma: CGFloat = 0.5

    /// The two colours the mark comes in.
    enum MarkColor: Equatable {
        case black, white

        var uiColor: UIColor { self == .black ? .black : .white }
        var color: Color { self == .black ? .black : .white }
    }

    /// Where the mark goes on an image of `imageSize`, for artwork whose
    /// height/width is `markAspectRatio`: top-trailing, inset.
    static func markRect(in imageSize: CGSize, markAspectRatio: CGFloat) -> CGRect {
        let shorter = min(imageSize.width, imageSize.height)
        let width = shorter * markSizeFraction
        let padding = shorter * markPaddingFraction
        return CGRect(x: imageSize.width - width - padding, y: padding, width: width, height: width * markAspectRatio)
    }

    /// Black or white, for a mark drawn at `rect` on `image` (both in the
    /// image's own point space, as `markRect` returns). Draws the box into a
    /// 32×32 bitmap with no interpolation — one nearest pixel per grid cell,
    /// the same points the Lambda samples — and averages their luma.
    static func markColor(for image: UIImage, in rect: CGRect) -> MarkColor {
        let n = colorSampleGrid
        guard rect.width > 0, rect.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return .white }
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            // UIKit's top-left origin, so `UIImage.draw` applies the
            // image's orientation the same way the watermark draw does.
            context.translateBy(x: 0, y: CGFloat(n))
            context.scaleBy(x: 1, y: -1)
            let sx = CGFloat(n) / rect.width, sy = CGFloat(n) / rect.height
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(
                x: -rect.minX * sx, y: -rect.minY * sy,
                width: image.size.width * sx, height: image.size.height * sy
            ))
            UIGraphicsPopContext()
            return true
        }
        guard drew else { return .white }
        var total: CGFloat = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            total += (0.2126 * CGFloat(pixels[i]) + 0.7152 * CGFloat(pixels[i + 1]) + 0.0722 * CGFloat(pixels[i + 2])) / 255
        }
        return total / CGFloat(n * n) > lightBackgroundLuma ? .black : .white
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
            // Decided from the photo before anything is drawn on it.
            let tinted = markImage.withTintColor(
                PhotoWatermarker.markColor(for: baseImage, in: markRect).uiColor,
                renderingMode: .alwaysOriginal
            )

            let format = UIGraphicsImageRendererFormat()
            format.scale = baseImage.scale
            let output = UIGraphicsImageRenderer(size: baseImage.size, format: format).image { _ in
                baseImage.draw(in: CGRect(origin: .zero, size: baseImage.size))
                tinted.draw(in: markRect)
            }

            guard let jpegData = output.jpegData(compressionQuality: 0.95) else {
                throw PhotoWatermarkerError.encodeFailed
            }
            return jpegData
        }.value
    }
}
