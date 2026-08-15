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

    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                header

                if !appState.processingPhotoIDs.isEmpty || !appState.failedPhotoIDs.isEmpty {
                    PendingPhotosBanner()
                }

                Text("Privacy: \(appState.user.privacy.rawValue)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)

                if appState.photos.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.textSecondary)
                        Text("No photos yet. Take your first one!")
                            .foregroundStyle(Theme.textSecondary)
                            .font(.system(size: 14))
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(appState.photos) { photo in
                                PhotoThumbnail(
                                    photo: photo,
                                    selectionState: isSelecting
                                        ? (selectedPhotoIDs.contains(photo.id) ? .selected : .unselected)
                                        : .inactive
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
            .padding(20)
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
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        selectedPhotoIDs.removeAll()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white)
                    }
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
                .disabled(isDeleting)
            }
        } else {
            HStack {
                HStack(spacing: 6) {
                    Text(appState.user.username.isEmpty ? "You" : appState.user.username)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    if appState.user.verificationStatus == .verified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.success)
                    }
                }
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.white)
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
                debugPrint(error)
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
