//
//  CameraCaptureView.swift
//  the-human-internet
//

import SwiftUI
import UIKit

struct CameraCaptureView: View {
    @Environment(AppState.self) private var appState
    @State private var showCongrats = false
    @State private var isUploading = false
    @State private var errorMessage: String?

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
                            .overlay {
                                if isUploading {
                                    ProgressView().tint(Theme.background)
                                }
                            }
                    }
                    .disabled(isUploading)
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
        .alert(
            "Couldn't upload photo",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    /// Stand-in for real camera capture until AVFoundation + C2PA integration
    /// replaces this. Deliberately uploads a single bundled asset rather than
    /// anything from the photo library — importing existing images would break
    /// the "taken live by a human" guarantee this whole feature exists for.
    private func capture() {
        guard let userID = appState.user.id else { return }
        guard let data = UIImage(named: "CaptureStandIn")?.jpegData(compressionQuality: 0.9) else {
            errorMessage = "Missing stand-in capture asset."
            return
        }
        isUploading = true

        Task {
            defer { isUploading = false }
            do {
                // `appState.photos` is hydrated from the DB on launch, so this
                // reflects whether they've ever posted before — not just whether
                // they've seen the modal this session.
                let isFirstPhoto = appState.photos.isEmpty
                let photo = try await PhotoRepository.upload(imageData: data, userID: userID)
                appState.photos.insert(photo, at: 0)

                if isFirstPhoto {
                    showCongrats = true
                }
            } catch {
                errorMessage = "Please try again."
                debugPrint(error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CameraCaptureView()
            .environment(AppState())
    }
}
