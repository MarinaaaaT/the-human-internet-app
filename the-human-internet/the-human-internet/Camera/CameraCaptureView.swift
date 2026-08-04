//
//  CameraCaptureView.swift
//  the-human-internet
//

import SwiftUI

struct CameraCaptureView: View {
    @Environment(AppState.self) private var appState
    @State private var showCongrats = false
    @State private var navigateToPhoto: VerifiedPhoto?

    private let placeholderSymbols = ["pawprint.fill", "camera.fill", "sun.max.fill", "leaf.fill", "figure.walk"]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack {
                Spacer()
                Image(systemName: "viewfinder")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()

                ZStack {
                    HStack {
                        if let last = appState.photos.first {
                            NavigationLink(value: last) {
                                PhotoThumbnail(photo: last)
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                        } else {
                            Color.clear.frame(width: 48, height: 48)
                        }
                        Spacer()
                    }

                    Button {
                        capture()
                    } label: {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 4).padding(4))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .navigationDestination(for: VerifiedPhoto.self) { photo in
            PhotoDetailView(photo: photo)
        }
        .sheet(isPresented: $showCongrats) {
            CongratsSheetView()
        }
    }

    private func capture() {
        let symbol = placeholderSymbols.randomElement() ?? "pawprint.fill"
        let photo = VerifiedPhoto(symbol: symbol, tint: Theme.accentPink, privacy: appState.user.privacy, capturedAt: .now)
        appState.photos.insert(photo, at: 0)

        if !appState.hasSeenFirstPhotoCongrats {
            appState.hasSeenFirstPhotoCongrats = true
            showCongrats = true
        }
    }
}

#Preview {
    NavigationStack {
        CameraCaptureView()
            .environment(AppState())
    }
}
