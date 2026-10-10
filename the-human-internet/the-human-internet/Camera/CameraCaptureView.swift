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
    /// Bumped per capture; drives the shutter haptic.
    @State private var captureCount = 0

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
            Theme.foreground
                .ignoresSafeArea()
                .opacity(shutterFlash)
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    HumanIconButton(
                        systemName: "arrow.triangle.2.circlepath.camera",
                        accessibilityLabel: "Flip camera",
                        surface: .media
                    ) {
                        cameraSession.flipCamera()
                    }
                }
                .padding(.horizontal, DesignTokens.Space.s6)
                .padding(.top, DesignTokens.Space.s3)

                Spacer()

                ZStack {
                    HStack {
                        if let last = appState.photos.first {
                            NavigationLink(value: last) {
                                PhotoThumbnail(
                                    photo: last,
                                    uploadState: appState.uploadState(for: last.id),
                                    isProvisional: appState.provisionalPhotoIDs.contains(last.id),
                                    onRetry: {
                                        PhotoUploadQueue.retry(photoID: last.id, appState: appState)
                                    }
                                )
                                    .frame(width: DesignTokens.Size.iconButton, height: DesignTokens.Size.iconButton)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                            }
                            .accessibilityLabel("Last photo")
                        } else {
                            Color.clear.frame(width: DesignTokens.Size.iconButton, height: DesignTokens.Size.iconButton)
                        }
                        Spacer()
                    }

                    Button {
                        capture()
                    } label: {
                        // The shutter: a white disc ringed in black — the one
                        // control big enough to find without looking.
                        Circle()
                            .fill(Theme.background)
                            .frame(width: DesignTokens.Space.s16, height: DesignTokens.Space.s16)
                            .overlay(Circle().stroke(Theme.foreground, lineWidth: 2).padding(DesignTokens.Space.s1))
                    }
                    .accessibilityLabel("Take photo")
                    // Soft impact on capture — one of the two moments the
                    // design system allows a haptic.
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: captureCount)
                }
                .padding(.horizontal, DesignTokens.Space.s8)
                .padding(.bottom, DesignTokens.Space.s6)
            }
        }
    }

    private var noCameraAvailableView: some View {
        VStack(spacing: DesignTokens.Space.s4) {
            Image(systemName: "camera.metering.unknown")
                .symbolStyle(DesignTokens.TextStyles.h1)
                .foregroundStyle(Theme.mutedForeground)
            Text("No camera available.")
                .textStyle(DesignTokens.TextStyles.title)
                .foregroundStyle(Theme.foreground)
            Text("This device doesn't have a usable camera — the Simulator, for instance, has none. Try a physical iPhone.")
                .textStyle(DesignTokens.TextStyles.body)
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(DesignTokens.Space.s8)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: DesignTokens.Space.s4) {
            Image(systemName: "camera")
                .symbolStyle(DesignTokens.TextStyles.h1)
                .foregroundStyle(Theme.mutedForeground)
            Text("Camera access is off.")
                .textStyle(DesignTokens.TextStyles.title)
                .foregroundStyle(Theme.foreground)
            Text("Turn on camera access in Settings to take a photo.")
                .textStyle(DesignTokens.TextStyles.body)
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .textStyle(DesignTokens.TextStyles.label)
                    .padding(.horizontal, DesignTokens.Space.s6)
                    .ctaStyle()
            }
            .buttonStyle(.plain)
            .padding(.top, DesignTokens.Space.s1)
        }
        .padding(DesignTokens.Space.s8)
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
        captureCount += 1

        Task {
            do {
                let imageData = try await cameraSession.capturePhoto()

                // Best-effort and independent of everything below: the
                // user's own untouched capture — no watermark, no C2PA
                // manifest, since nobody but them ever sees this copy. It's
                // the fallback if the upload never finishes, so it's fired
                // off rather than awaited here.
                Task.detached(priority: .utility) {
                    do {
                        try await PhotoLibrarySaver.save(imageData: imageData)
                    } catch {
                        // Still best-effort — the upload path is the one that
                        // matters — but a denied-Photos-access failure was
                        // previously silent; at least surface it now.
                        Log.camera.error("Photo library backup save failed: \(error, privacy: .public)")
                    }
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
                Log.camera.error("Capture failed: \(error, privacy: .public)")
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
