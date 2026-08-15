//
//  PhotoDetailView.swift
//  the-human-internet
//

import SwiftUI

struct PhotoDetailView: View {
    let photo: VerifiedPhoto

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .disabled(isDeleting)
            }
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deletePhoto() }
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
            ShareSheetView(photo: photo)
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
            PhotoVerificationView(photoID: photo.id)
        }
        // The real, live public page — the website's own server-side privacy
        // check (Public vs. Humans Only) applies exactly as it would for any
        // other signed-out visitor.
        .sheet(isPresented: $showWebPreview) {
            WebPreviewView(url: photo.verificationURL)
        }
    }

    private func deletePhoto() {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await PhotoRepository.delete(photo: photo)
                PhotoUploadQueue.cancelPendingUpload(photoID: photo.id, appState: appState)
                appState.photos.removeAll { $0.id == photo.id }
                dismiss()
            } catch {
                deleteError = "Please try again."
                Log.photos.error("Delete failed for \(photo.id, privacy: .public): \(error, privacy: .public)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        PhotoDetailView(photo: VerifiedPhoto(id: UUID(), userID: UUID(), storagePath: "preview/example.jpg", capturedAt: .now, verificationDeepLink: "thehumaninternet://photo/preview", shortCode: "preview1"))
    }
}
