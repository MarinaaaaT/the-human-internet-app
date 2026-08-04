//
//  PhotoThumbnail.swift
//  the-human-internet
//

import SwiftUI

struct PhotoThumbnail: View {
    let photo: VerifiedPhoto

    var body: some View {
        RemotePhotoImage(storagePath: photo.storagePath)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
    }
}

#Preview {
    PhotoThumbnail(photo: VerifiedPhoto(id: UUID(), userID: UUID(), storagePath: "preview/example.jpg", capturedAt: .now))
        .frame(width: 120, height: 120)
}
