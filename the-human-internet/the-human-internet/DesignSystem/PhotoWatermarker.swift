//
//  PhotoWatermarker.swift
//  the-human-internet
//

import SwiftUI
import UIKit

enum PhotoWatermarkerError: Error {
    case invalidImage
    case renderFailed
    case encodeFailed
}

/// Burns the `BrandMark` logo into a captured JPEG's actual pixels — not
/// just the in-app UI overlay `PhotoDetailView` draws over it — so the mark
/// travels with the photo wherever it's uploaded, shared, or downloaded.
/// Deliberately not applied to the copy saved to the user's own device
/// Photos library, which stays an untouched copy of exactly what they shot.
enum PhotoWatermarker {
    /// Runs the compositing off the main actor — real work at full photo
    /// resolution — but renders the small, fixed-size mark itself on the
    /// main actor first, since `ImageRenderer` requires it.
    static func watermark(imageData: Data) async throws -> Data {
        guard let baseImage = UIImage(data: imageData) else {
            throw PhotoWatermarkerError.invalidImage
        }

        let markImage = try await MainActor.run { () -> UIImage in
            let markSize = min(baseImage.size.width, baseImage.size.height) * 0.09
            let renderer = ImageRenderer(content: BrandMark(size: markSize, color: Theme.accentPink))
            renderer.scale = baseImage.scale
            guard let markImage = renderer.uiImage else {
                throw PhotoWatermarkerError.renderFailed
            }
            return markImage
        }

        return try await Task.detached(priority: .userInitiated) {
            // Matches the top-trailing placement of the in-app overlay.
            let padding = min(baseImage.size.width, baseImage.size.height) * 0.035
            let origin = CGPoint(
                x: baseImage.size.width - markImage.size.width - padding,
                y: padding
            )

            let format = UIGraphicsImageRendererFormat()
            format.scale = baseImage.scale
            let output = UIGraphicsImageRenderer(size: baseImage.size, format: format).image { _ in
                baseImage.draw(in: CGRect(origin: .zero, size: baseImage.size))
                markImage.draw(at: origin)
            }

            guard let jpegData = output.jpegData(compressionQuality: 0.95) else {
                throw PhotoWatermarkerError.encodeFailed
            }
            return jpegData
        }.value
    }
}
