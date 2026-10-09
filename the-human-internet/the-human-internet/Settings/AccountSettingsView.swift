//
//  AccountSettingsView.swift
//  the-human-internet
//

import SwiftUI

/// Settings → Account Settings: the Photo Fingerprint switch, and deleting
/// the account. Pushed onto Settings' `NavigationStack` rather than shown as
/// a sheet, so the delete confirmation can be one without stacking sheets
/// three deep.
struct AccountSettingsView: View {
    /// Called once the account is gone and local state has been cleared —
    /// Settings uses it to dismiss itself, the same as after Log Out.
    let onAccountDeleted: () -> Void

    @Environment(AppState.self) private var appState
    @State private var showDeleteConfirmation = false
    @State private var watermarkErrorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Toggle(isOn: watermarkBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Photo Fingerprint")
                            .font(Theme.font(size: 16, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(appState.isWatermarkEnabled
                             ? "New photos are visibly watermarked."
                             : "New photos are not visibly watermarked.")
                            .font(Theme.font(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.selection)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                if let watermarkErrorMessage {
                    Text(watermarkErrorMessage)
                        .font(Theme.font(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
                Divider().overlay(Theme.divider)

                // A plain row, like Log Out — the confirmation sheet is where
                // the weight of this goes, not the row.
                Button {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Text("Delete Your Account")
                            .font(Theme.font(size: 16, weight: .medium))
                        Spacer()
                        Image(systemName: "trash")
                    }
                    .foregroundStyle(Theme.ctaForeground)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }

                Spacer()
            }
            .padding(.top, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Account Settings")
                    .font(Theme.font(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .sheet(isPresented: $showDeleteConfirmation) {
            DeleteAccountConfirmationSheet(onDeleted: {
                showDeleteConfirmation = false
                onAccountDeleted()
            })
        }
    }

    /// Writes through on every flip, optimistic with revert — there's no
    /// Save button for a switch.
    private var watermarkBinding: Binding<Bool> {
        Binding(
            get: { appState.isWatermarkEnabled },
            set: { enabled in
                watermarkErrorMessage = nil
                Task {
                    do {
                        try await appState.setWatermarkEnabled(enabled)
                    } catch {
                        watermarkErrorMessage = "Couldn't save — please try again."
                        Log.settings.error("Photo Fingerprint update failed: \(error, privacy: .public)")
                    }
                }
            }
        )
    }
}

/// The "are you sure" for deleting an account. A sheet rather than an
/// `.alert` because an alert's message can't carry the bold "permanently".
private struct DeleteAccountConfirmationSheet: View {
    let onDeleted: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                SheetGrabber()

                Text("Delete Your Account")
                    .font(Theme.font(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                (Text("Although we save all photos to your camera roll, they are saved unverified. Deleting your account will ")
                    + Text("permanently").font(Theme.font(size: 15, weight: .bold))
                    + Text(" delete signed, C2PA verified photos unless you have downloaded them. Would you like to proceed?"))
                    .font(Theme.font(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.font(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                }

                HStack(spacing: 12) {
                    SecondaryButton(title: isDeleting ? "Deleting…" : "Yes") {
                        deleteAccount()
                    }
                    .disabled(isDeleting)
                    PrimaryButton(title: "No", isEnabled: !isDeleting) {
                        dismiss()
                    }
                }
            }
            .padding(24)
            .padding(.top, 16)
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.background)
        // Swiping away mid-delete wouldn't stop it, only hide whether it
        // worked.
        .interactiveDismissDisabled(isDeleting)
    }

    private func deleteAccount() {
        errorMessage = nil
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await appState.deleteAccount()
                onDeleted()
            } catch {
                errorMessage = "Couldn't delete your account — please try again."
                Log.settings.error("Account deletion failed: \(error, privacy: .public)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        AccountSettingsView(onAccountDeleted: {})
            .environment(AppState())
    }
}
