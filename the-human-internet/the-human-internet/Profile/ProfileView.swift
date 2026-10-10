//
//  ProfileView.swift
//  the-human-internet
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var showSettings = false

    @State private var selectedPhotoIDs: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    /// Driven manually (rather than `NavigationLink`) so a tile's tap and
    /// long-press gestures can be made mutually exclusive — see the grid
    /// below for why.
    @State private var navigateTo: VerifiedPhoto?

    /// Selection mode has no separate flag — it *is* a non-empty selection,
    /// so deselecting every photo exits it automatically.
    private var isSelecting: Bool { !selectedPhotoIDs.isEmpty }

    private let columns = [GridItem(.flexible(), spacing: DesignTokens.Space.s1), GridItem(.flexible(), spacing: DesignTokens.Space.s1)]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
                header

                if !appState.processingPhotoIDs.isEmpty || !appState.failedPhotoIDs.isEmpty {
                    PendingPhotosBanner()
                }

                Text("Privacy: \(appState.user.privacy.rawValue)")
                    .textStyle(DesignTokens.TextStyles.label)
                    .foregroundStyle(Theme.mutedForeground)

                if appState.photos.isEmpty {
                    Spacer()
                    // Empty state: one doodle, two beats.
                    VStack(spacing: DesignTokens.Space.s4) {
                        Image("DoodleHand")
                            .resizable()
                            .scaledToFit()
                            .frame(width: DesignTokens.Size.thumbnail, height: DesignTokens.Size.thumbnail)
                            .accessibilityHidden(true)
                        LabelValue(label: "No photos yet.", value: "Take your first one.")
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: DesignTokens.Space.s1) {
                            ForEach(appState.photos) { photo in
                                PhotoThumbnail(
                                    photo: photo,
                                    selectionState: isSelecting
                                        ? (selectedPhotoIDs.contains(photo.id) ? .selected : .unselected)
                                        : .inactive,
                                    uploadState: appState.uploadState(for: photo.id),
                                    isProvisional: appState.provisionalPhotoIDs.contains(photo.id),
                                    onRetry: {
                                        PhotoUploadQueue.retry(photoID: photo.id, appState: appState)
                                    }
                                )
                                .contentShape(Rectangle())
                                // `NavigationLink` has its own built-in tap
                                // recognizer that a `.simultaneousGesture`
                                // long-press can't suppress — releasing a
                                // long-press also fired the link's tap and
                                // pushed the detail view. `.exclusively`
                                // makes the two gestures mutually exclusive:
                                // whichever's threshold is met first wins,
                                // the other never fires.
                                .gesture(
                                    LongPressGesture()
                                        .onEnded { _ in
                                            if isSelecting {
                                                toggleSelection(photo)
                                            } else {
                                                selectedPhotoIDs.insert(photo.id)
                                            }
                                        }
                                        .exclusively(before: TapGesture().onEnded {
                                            if isSelecting {
                                                toggleSelection(photo)
                                            } else {
                                                navigateTo = photo
                                            }
                                        })
                                )
                            }
                        }
                    }
                    .sensoryFeedback(.selection, trigger: isSelecting)
                }
            }
            .padding(DesignTokens.Space.s6)
        }
        .navigationDestination(item: $navigateTo) { photo in
            PhotoDetailView(photo: photo)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .confirmationDialog(
            "Are you sure you would like to delete \(selectedPhotoIDs.count) photo\(selectedPhotoIDs.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes them and their verification links. They'll stay in your device's photo library.")
        }
        .alert(
            "Couldn't delete photos",
            isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
        ) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var header: some View {
        if isSelecting {
            HStack {
                Text("\(selectedPhotoIDs.count) photo\(selectedPhotoIDs.count == 1 ? "" : "s") selected")
                    .textStyle(DesignTokens.TextStyles.title)
                    .foregroundStyle(Theme.foreground)
                Spacer()
                HStack(spacing: DesignTokens.Space.s3) {
                    HumanIconButton(systemName: "xmark", accessibilityLabel: "Cancel selection") {
                        selectedPhotoIDs.removeAll()
                    }
                    HumanIconButton(systemName: "trash", accessibilityLabel: "Delete selected photos") {
                        showDeleteConfirmation = true
                    }
                }
                .disabled(isDeleting)
            }
        } else {
            HStack {
                HStack(spacing: DesignTokens.Space.s2) {
                    Text(appState.user.username.isEmpty ? "You" : appState.user.username)
                        .textStyle(DesignTokens.TextStyles.h3)
                        .foregroundStyle(Theme.foreground)
                    if appState.user.verificationStatus == .verified {
                        VerifiedBadge()
                    }
                }
                Spacer()
                HumanIconButton(systemName: "gearshape", accessibilityLabel: "Settings") {
                    showSettings = true
                }
            }
        }
    }

    private func toggleSelection(_ photo: VerifiedPhoto) {
        if selectedPhotoIDs.contains(photo.id) {
            selectedPhotoIDs.remove(photo.id)
        } else {
            selectedPhotoIDs.insert(photo.id)
        }
    }

    private func deleteSelected() {
        let targets = appState.photos.filter { selectedPhotoIDs.contains($0.id) }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await PhotoRepository.delete(photos: targets)
                for photo in targets {
                    PhotoUploadQueue.cancelPendingUpload(photoID: photo.id, appState: appState)
                }
                appState.photos.removeAll { selectedPhotoIDs.contains($0.id) }
                selectedPhotoIDs.removeAll()
            } catch {
                deleteError = "Please try again."
                Log.photos.error("Batch delete failed: \(error, privacy: .public)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environment(AppState())
    }
}
