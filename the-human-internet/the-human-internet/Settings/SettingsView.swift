//
//  SettingsView.swift
//  the-human-internet
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var showPrivacySheet = false
    @State private var showVerificationInfo = false
    @State private var showEditUsername = false
    @State private var showSignOutConfirmation = false
    @State private var signOutErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    settingsRow(title: "Username", value: appState.user.username.isEmpty ? "—" : appState.user.username, icon: "pencil") {
                        showEditUsername = true
                    }
                    Divider().overlay(Color.white.opacity(0.08))
                    settingsRow(title: "Privacy", value: appState.user.privacy.rawValue, icon: "pencil") {
                        showPrivacySheet = true
                    }
                    Divider().overlay(Color.white.opacity(0.08))
                    settingsRow(title: "Verification Status", value: statusLabel, valueColor: statusColor, icon: "info.circle") {
                        showVerificationInfo = true
                    }
                    Divider().overlay(Color.white.opacity(0.08))

                    Button {
                        showSignOutConfirmation = true
                    } label: {
                        HStack {
                            Text("Log Out")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.red)
                            Spacer()
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }

                    Spacer()
                }
                .padding(.top, 8)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showPrivacySheet) {
            PrivacyEditSheet()
        }
        .sheet(isPresented: $showVerificationInfo) {
            VerificationStatusSheet()
        }
        .sheet(isPresented: $showEditUsername) {
            EditUsernameSheet()
        }
        .confirmationDialog("Log out of the human internet?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Couldn't log out",
            isPresented: Binding(get: { signOutErrorMessage != nil }, set: { if !$0 { signOutErrorMessage = nil } })
        ) {
            Button("OK") { signOutErrorMessage = nil }
        } message: {
            Text(signOutErrorMessage ?? "Please try again.")
        }
    }

    private func signOut() {
        Task {
            do {
                try await appState.signOut()
                dismiss()
            } catch {
                signOutErrorMessage = "Please try again."
                Log.auth.error("Sign-out failed: \(error, privacy: .public)")
            }
        }
    }

    private var statusLabel: String {
        switch appState.user.verificationStatus {
        case .inProgress: return "In progress"
        case .verified: return "Verified"
        case .failed: return "Failed"
        }
    }

    private var statusColor: Color {
        switch appState.user.verificationStatus {
        case .inProgress: return Theme.warning
        case .verified: return Theme.success
        case .failed: return .red
        }
    }

    private func settingsRow(title: String, value: String, valueColor: Color = .white, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Text(value)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(valueColor)
                }
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
