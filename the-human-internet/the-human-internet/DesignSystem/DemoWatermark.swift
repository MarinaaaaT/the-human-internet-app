//
//  DemoWatermark.swift
//  the-human-internet
//

import UIKit

/// "DEMO", drawn across the middle of every photo the demo account takes: a
/// white outline with a transparent fill. Burned into the pixels by
/// `PhotoWatermarker` in the same pass as the fingerprint, and drawn over a
/// photo still waiting on that by `ProvisionalWatermark` — both through
/// `draw(in:)`, so the swap from one to the other moves nothing.
///
/// Sized from the image, like the fingerprint, so any resolution comes out
/// the same: the word spans `widthFraction` of the shorter side, centred on
/// its capital letters.
enum DemoWatermark {
    static let text = "DEMO"
    /// The word's width as a fraction of the image's shorter side.
    static let widthFraction: CGFloat = 0.7
    /// Outline thickness as a percentage of the font size. Positive, which
    /// is what makes `NSAttributedString` stroke the glyphs without filling
    /// them.
    static let strokeWidthPercent: CGFloat = 3
    /// The design system's one cut, set by name rather than through
    /// `Typography`: the mark burned into a photo mustn't change with the
    /// app's font flag.
    static let fontName = "InterDisplay-Medium"

    /// Draws the word into the current UIKit graphics context, centred on a
    /// canvas of `size`.
    static func draw(in size: CGSize) {
        let shorter = min(size.width, size.height)
        let reference = font(ofSize: 100)
        let referenceWidth = (text as NSString).size(withAttributes: [.font: reference]).width
        guard shorter > 0, referenceWidth > 0 else { return }

        let font = font(ofSize: 100 * shorter * widthFraction / referenceWidth)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .strokeColor: UIColor.white,
            .strokeWidth: strokeWidthPercent,
        ]
        let width = (text as NSString).size(withAttributes: attributes).width
        // `draw(at:)` places the top of the line box; the baseline sits
        // `ascender` below it. Centring the capitals, not the line box, keeps
        // the word optically in the middle.
        let baseline = size.height / 2 + font.capHeight / 2
        (text as NSString).draw(
            at: CGPoint(x: (size.width - width) / 2, y: baseline - font.ascender),
            withAttributes: attributes
        )
    }

    /// The word alone on a transparent image of `size`, for drawing over a
    /// photo on screen. Cached per size: a grid of thumbnails shares one.
    static func overlayImage(size: CGSize) -> UIImage {
        let key = "\(size.width)x\(size.height)" as NSString
        if let cached = overlayCache.object(forKey: key) { return cached }
        let image = UIGraphicsImageRenderer(size: size).image { _ in draw(in: size) }
        overlayCache.setObject(image, forKey: key)
        return image
    }

    private static let overlayCache = NSCache<NSString, UIImage>()

    private static func font(ofSize size: CGFloat) -> UIFont {
        UIFont(name: fontName, size: size) ?? .systemFont(ofSize: size, weight: .medium)
    }
}
