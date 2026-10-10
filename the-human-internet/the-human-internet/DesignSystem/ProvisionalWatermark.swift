//
//  ProvisionalWatermark.swift
//  the-human-internet
//

import SwiftUI

/// The brand mark drawn *over* a photo whose pixels don't carry it yet — a
/// raw capture still waiting on the watermark to be burned in (on device or,
/// with `server_side_watermark`, by the signing Lambda). Same artwork
/// (`PhotoWatermarker.markAssetName`), same placement
/// (`PhotoWatermarker.markRect`) as the burned-in mark, so when the real
/// watermarked photo replaces the raw one, nothing appears to move.
///
/// Must be overlaid on the image view itself, *before* any clipping, so its
/// frame is the whole image even where a `.fill` thumbnail crops it.
///
/// `color` is `PhotoWatermarker.markColor` for the photo underneath — the
/// same black-or-white choice the burned-in mark will make (see
/// `RemotePhotoImage`, which works it out once per loaded image).
struct ProvisionalWatermark: View {
    var color: PhotoWatermarker.MarkColor = .white

    var body: some View {
        GeometryReader { geometry in
            if let mark = UIImage(named: PhotoWatermarker.markAssetName), mark.size.width > 0 {
                let rect = PhotoWatermarker.markRect(
                    in: geometry.size,
                    markAspectRatio: mark.size.height / mark.size.width
                )
                Image(uiImage: mark)
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(color.color)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    Color.gray
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .overlay { ProvisionalWatermark(color: .black) }
        .padding()
}
