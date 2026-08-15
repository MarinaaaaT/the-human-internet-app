//
//  CameraCaptureView.swift
//  the-human-internet
//

import SwiftUI
import UIKit

struct CameraCaptureView: View {
    @Environment(AppState.self) private var appState
    @State private var cameraSession = CameraSession()
    @State private var showCongrats = false
    @State private var errorMessage: String?
    /// Drives the shutter blink over the preview. Purely cosmetic — it never
    /// gates capture, so rapid taps still all go through.
    @State private var shutterFlash = 0.0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch cameraSession.authorizationState {
            case .notDetermined:
                EmptyView()
            case .denied:
                permissionDeniedView
            case .authorized:
                if cameraSession.isCameraAvailable {
                    cameraView
                } else {
                    noCameraAvailableView
                }
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
        .task {
            await cameraSession.requestAuthorizationIfNeeded()
            cameraSession.start()
        }
        .onDisappear {
            cameraSession.stop()
        }
    }

    private var cameraView: some View {
        ZStack {
            CameraPreviewView(session: cameraSession.session)
                .ignoresSafeArea()

            // Sits above the preview but below the controls, so only the
            // viewfinder blinks — matching the system Camera app, where the
            // shutter and chrome stay visible through the flash.
            Color.black
                .ignoresSafeArea()
                .opacity(shutterFlash)
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        cameraSession.flipCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

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
    }

    private var noCameraAvailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("No camera available")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text("This device doesn't have a usable camera — the Simulator, for instance, has none. Try a physical iPhone.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("Camera access is off")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text("Turn on camera access in Settings to take a photo.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.accentBlue)
            .padding(.top, 4)
        }
        .padding(32)
    }

    /// Blinks the viewfinder to black and back. Driven from the tap rather
    /// than from capture completion, so the feedback lands at the moment of
    /// the press even while an earlier capture is still being processed.
    private func flashShutter() {
        withAnimation(.linear(duration: 0.05)) {
            shutterFlash = 1
        } completion: {
            withAnimation(.easeOut(duration: 0.12)) {
                shutterFlash = 0
            }
        }
    }

    private func capture() {
        guard let userID = appState.user.id else { return }
        flashShutter()

        Task {
            do {
                let imageData = try await cameraSession.capturePhoto()

                // Best-effort and independent of everything below: the
                // user's own untouched capture — no watermark, no C2PA
                // manifest, since nobody but them ever sees this copy. It's
                // the fallback if the upload never finishes, so it's fired
                // off rather than awaited here.
                Task.detached(priority: .utility) {
                    try? await PhotoLibrarySaver.save(imageData: imageData)
                }

                // `appState.photos` is hydrated from the DB on launch, so this
                // reflects whether they've ever posted before — not just whether
                // they've seen the modal this session.
                let isFirstPhoto = appState.photos.isEmpty

                // Persists the raw capture to disk and starts watermarking,
                // signing, and the network upload in the background — this
                // returns as soon as the photo is safely queued, not once
                // it's actually processed.
                let photo = try PhotoUploadQueue.enqueue(imageData: imageData, userID: userID, appState: appState)
                appState.photos.insert(photo, at: 0)

                if isFirstPhoto {
                    showCongrats = true
                }
            } catch CameraSessionError.noCameraAvailable {
                errorMessage = "No camera is available on this device."
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
