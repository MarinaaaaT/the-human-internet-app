//
//  BrandMark.swift
//  the-human-internet
//

import SwiftUI

/// The spiral "imprint" — the brand's one hand-made shape, and the only way
/// the app says *verified*. Drawn from the `BrandMark` asset (the same
/// mark.svg as the website's public/brand/), as a template image so it takes
/// `color`: black on the page, white over a photo.
///
/// Not the watermark: that is `BrandMarkWatermark`, a PNG shared with the
/// signing Lambda — see `PhotoWatermarker`.
struct BrandMark: View {
    /// Height in points; the width follows the artwork.
    var size: CGFloat = DesignTokens.Size.icon
    var color: Color = DesignTokens.Colors.foreground

    var body: some View {
        Image("BrandMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// "the human ~ internet". Always lowercase, never re-set in type.
struct Wordmark: View {
    /// Height in points; the width follows the artwork.
    var height: CGFloat = DesignTokens.Space.s4
    var color: Color = DesignTokens.Colors.foreground

    var body: some View {
        Image("Wordmark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(color)
            .accessibilityLabel("the human internet")
    }
}

#Preview {
    VStack(spacing: DesignTokens.Space.s8) {
        BrandMark(size: DesignTokens.Size.thumbnail)
        Wordmark()
    }
    .padding()
    .background(Theme.background)
}
