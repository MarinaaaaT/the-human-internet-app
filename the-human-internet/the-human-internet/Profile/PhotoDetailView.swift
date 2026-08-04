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
                    RoundedRectangle(cornerRadius: 20)
                        .fill(photo.tint.opacity(0.18))
                    Image(systemName: photo.symbol)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: 110)
                        .foregroundStyle(photo.tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        PhotoDetailView(photo: VerifiedPhoto(symbol: "pawprint.fill", tint: Theme.accentPink, privacy: .public_, capturedAt: .now))
    }
}
