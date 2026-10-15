//
//  PhotoDetailView.swift
//  the-human-internet
//

import SwiftUI

struct PhotoDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// The photo on screen. Seeded with the one that was tapped, then moved
    /// by swiping — the buttons and the toolbar always act on this one.
    @State private var currentPhotoID: UUID

    @State private var showShareSheet = false
    @State private var showPreviewSheet = false
    /// Captured when "Continue" is tapped in `PreviewAsSheetView`, then acted
    /// on once that sheet has actually finished dismissing — presenting a
    /// new sheet/cover in the same beat as dismissing this one is unreliable.
    @State private var pendingPreviewAudience: PreviewAudience?
    @State private var showAppPreview = false
    @State private var showWebPreview = false

    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    init(photo: VerifiedPhoto) {
        _currentPhotoID = State(initialValue: photo.id)
    }

    /// The same list, in the same order, as the Profile grid — so swiping
    /// left walks the grid forwards, newest to oldest.
    private var photos: [VerifiedPhoto] { appState.photos }

    private var currentPhoto: VerifiedPhoto? {
        photos.first { $0.id == currentPhotoID }
    }

    var body: some View {
        let currentIndex = photos.firstIndex { $0.id == currentPhotoID }
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                // The photo tracks the finger, like the grid does when it
                // scrolls — that's the user moving it, not an animation, so
                // it sits outside the opacity-only motion rule.
                TabView(selection: $currentPhotoID) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        page(
                            for: photo,
                            isLoaded: currentIndex.map { Self.isWithinPreloadWindow(index, of: $0) } ?? false
                        )
                        .tag(photo.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: DesignTokens.Space.s3) {
                    SecondaryButton(title: "Preview") { showPreviewSheet = true }
                    PrimaryButton(title: "Share") { showShareSheet = true }
                }
                .disabled(currentPhoto == nil)
                .padding(.horizontal, DesignTokens.Space.s6)
                .padding(.bottom, DesignTokens.Space.s6)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.foreground)
                }
                .accessibilityLabel("Delete photo")
                .disabled(isDeleting || currentPhoto == nil)
            }
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let currentPhoto { deletePhoto(currentPhoto) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the photo and its verification link. It'll stay in your device's photo library.")
        }
        .alert(
            "Couldn't delete photo",
            isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
        ) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "Please try again.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let currentPhoto {
                ShareSheetView(photo: currentPhoto)
            }
        }
        .sheet(isPresented: $showPreviewSheet, onDismiss: {
            switch pendingPreviewAudience {
            case .fellowHuman:
                showAppPreview = true
            case .unknownLurker:
                showWebPreview = true
            case nil:
                break
            }
            pendingPreviewAudience = nil
        }) {
            PreviewAsSheetView { audience in
                pendingPreviewAudience = audience
                showPreviewSheet = false
            }
        }
        // The exact same view a `thehumaninternet://photo/{id}` link opens —
        // what any other signed-in app user would see.
        .fullScreenCover(isPresented: $showAppPreview) {
            PhotoVerificationView(photoID: currentPhotoID)
        }
        // The real, live public page — the website's own server-side privacy
        // check (Public vs. Humans Only) applies exactly as it would for any
        // other signed-out visitor.
        .sheet(isPresented: $showWebPreview) {
            if let currentPhoto {
                WebPreviewView(url: currentPhoto.verificationURL)
            }
        }
    }

    /// Only pages inside the preload window get a `RemotePhotoImage`; the
    /// rest are empty until a swipe brings them close. Each loaded page holds
    /// a full-resolution decode (~50MB for a 12MP capture), so this bounds
    /// memory at three of them however far someone swipes, rather than
    /// relying on how many pages the `TabView` happens to keep alive.
    @ViewBuilder
    private func page(for photo: VerifiedPhoto, isLoaded: Bool) -> some View {
        Group {
            if isLoaded {
                // No separate brand-mark overlay: the photo carries its own,
                // burned in — or, until it does, `RemotePhotoImage` draws a
                // provisional one in the same place.
                RemotePhotoImage(
                    photo: photo,
                    contentMode: .fit,
                    isProvisional: appState.provisionalPhotoIDs.contains(photo.id)
                )
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
            } else {
                Color.clear
            }
        }
        .padding(.horizontal, DesignTokens.Space.s6)
        .padding(.vertical, DesignTokens.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The open photo and one either side, so a swipe lands on a photo that
    /// has already loaded.
    static func isWithinPreloadWindow(_ index: Int, of currentIndex: Int) -> Bool {
        abs(index - currentIndex) <= 1
    }

    /// Where the pager lands after `photoID` is deleted: the photo a swipe
    /// left would have reached, or the one before it if that was the last.
    /// `nil` when nothing else is left.
    static func photoToShow(afterDeleting photoID: UUID, from photos: [VerifiedPhoto]) -> VerifiedPhoto? {
        guard let index = photos.firstIndex(where: { $0.id == photoID }) else { return nil }
        if photos.indices.contains(index + 1) { return photos[index + 1] }
        return index > 0 ? photos[index - 1] : nil
    }

    private func deletePhoto(_ photo: VerifiedPhoto) {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await PhotoRepository.delete(photo: photo)
                PhotoUploadQueue.cancelPendingUpload(photoID: photo.id, appState: appState)
                // Stays in the pager on a neighbouring photo, the way Photos
                // does, instead of dropping back to the grid. Moves before
                // the removal so the selection never names a missing page,
                // and only if this photo is still the one on screen — someone
                // who swiped away while the delete was in flight keeps their
                // place.
                let next = Self.photoToShow(afterDeleting: photo.id, from: photos)
                if currentPhotoID == photo.id, let next {
                    currentPhotoID = next.id
                }
                appState.photos.removeAll { $0.id == photo.id }
                if next == nil { dismiss() }
            } catch {
                deleteError = "Please try again."
                Log.photos.error("Delete failed for \(photo.id, privacy: .public): \(error, privacy: .public)")
            }
        }
    }
}

#Preview {
    let appState = AppState()
    appState.photos = (1...3).map { n in
        VerifiedPhoto(id: UUID(), userID: UUID(), storagePath: "preview/example-\(n).jpg", capturedAt: .now, verificationDeepLink: "thehumaninternet://photo/preview", shortCode: "preview\(n)")
    }
    return NavigationStack {
        PhotoDetailView(photo: appState.photos[0])
    }
    .environment(appState)
}
