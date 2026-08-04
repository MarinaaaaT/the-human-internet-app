//
//  PhotoThumbnail.swift
//  the-human-internet
//

import SwiftUI

struct PhotoThumbnail: View {
    let photo: VerifiedPhoto

    var body: some View {
        ZStack {
            photo.tint.opacity(0.25)
            Image(systemName: photo.symbol)
                .foregroundStyle(photo.tint)
                .font(.system(size: 28))
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
    }
}

#Preview {
    PhotoThumbnail(photo: VerifiedPhoto(symbol: "pawprint.fill", tint: Theme.accentPink, privacy: .public_, capturedAt: .now))
        .frame(width: 120, height: 120)
}
