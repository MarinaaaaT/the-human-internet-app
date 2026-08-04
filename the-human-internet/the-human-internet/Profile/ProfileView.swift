//
//  ProfileView.swift
//  the-human-internet
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var showSettings = false

    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
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
                                NavigationLink(value: photo) {
                                    PhotoThumbnail(photo: photo)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationDestination(for: VerifiedPhoto.self) { photo in
            PhotoDetailView(photo: photo)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environment(AppState())
    }
}
