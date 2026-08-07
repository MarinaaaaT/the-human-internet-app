//
//  PhotoDetailView.swift
//  the-human-internet
//

import SwiftUI

struct PhotoDetailView: View {
    let photo: VerifiedPhoto

    @State private var showShareSheet = false
    @State private var showPreviewSheet = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    RemotePhotoImage(photo: photo, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    BrandMark(size: 28)
                        .padding(16)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                HStack(spacing: 12) {
                    SecondaryButton(title: "Preview") { showPreviewSheet = true }
                    LightButton(title: "Share") { showShareSheet = true }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(photo: photo)
        }
        .sheet(isPresented: $showPreviewSheet) {
            PreviewAsSheetView()
        }
    }
}

#Preview {
    NavigationStack {
        PhotoDetailView(photo: VerifiedPhoto(id: UUID(), userID: UUID(), storagePath: "preview/example.jpg", capturedAt: .now, verificationDeepLink: "thehumaninternet://photo/preview"))
    }
}
