//
//  ProvisionalWatermark.swift
//  the-human-internet
//

import SwiftUI

/// The brand mark drawn *over* a photo whose pixels don't carry it yet — a
/// raw capture still waiting on the watermark to be burned in (on device or,
/// with `server_side_watermark`, by the signing Lambda). Laid out exactly as
/// `PhotoWatermarker` and the Lambda burn it: sized and inset from the
/// top-trailing corner by fractions of the image's shorter side. So when the
/// real watermarked photo replaces the raw one, nothing appears to move.
///
/// Must be overlaid on the image view itself, *before* any clipping, so its
/// frame is the whole image even where a `.fill` thumbnail crops it.
struct ProvisionalWatermark: View {
    var body: some View {
        GeometryReader { geometry in
            let shorter = min(geometry.size.width, geometry.size.height)
            let inset = shorter * PhotoWatermarker.markPaddingFraction
            BrandMark(size: shorter * PhotoWatermarker.markSizeFraction, color: Theme.accentPink)
                .padding(.top, inset)
                .padding(.trailing, inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    Color.gray
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .overlay { ProvisionalWatermark() }
        .padding()
}
