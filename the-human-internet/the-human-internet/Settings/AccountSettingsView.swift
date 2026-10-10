//
//  AccountSettingsView.swift
//  the-human-internet
//

import AuthenticationServices
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
                    VStack(alignment: .leading, spacing: DesignTokens.Space.s1) {
                        Text("Photo fingerprint")
                            .textStyle(DesignTokens.TextStyles.body)
                            .foregroundStyle(Theme.foreground)
                        Text(appState.isWatermarkEnabled
                             ? "New photos are visibly watermarked."
                             : "New photos are not visibly watermarked.")
                            .textStyle(DesignTokens.TextStyles.label)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                .tint(Theme.foreground)
                .padding(.horizontal, DesignTokens.Space.s6)
                .padding(.vertical, DesignTokens.Space.s4)

                if let watermarkErrorMessage {
                    Text(watermarkErrorMessage)
                        .textStyle(DesignTokens.TextStyles.label)
                        .foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DesignTokens.Space.s6)
                        .padding(.bottom, DesignTokens.Space.s3)
                }
                Divider().overlay(Theme.border)

                // A plain row, like Log Out — the confirmation sheet is where
                // the weight of this goes, not the row.
                Button {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Text("Delete your account")
                            .textStyle(DesignTokens.TextStyles.body)
                        Spacer()
                        Image(systemName: "trash")
                            .symbolStyle(DesignTokens.TextStyles.body)
                    }
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, DesignTokens.Space.s6)
                    .padding(.vertical, DesignTokens.Space.s4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, DesignTokens.Space.s2)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Account settings")
                    .textStyle(DesignTokens.TextStyles.title)
                    .foregroundStyle(Theme.foreground)
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
    @State private var reauthorization = AppleReauthorization()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DesignTokens.Space.s6) {
                SheetGrabber()

                Text("Delete your account?")
                    .textStyle(DesignTokens.TextStyles.h3)
                    .foregroundStyle(Theme.foreground)

                // One weight, so "permanently" is emphasised with colour and
                // an underline rather than bold.
                (Text("Although we save all photos to your camera roll, they are saved unverified. Deleting your account will ")
                    .foregroundStyle(Theme.mutedForeground)
                    + Text("permanently")
                        .foregroundStyle(Theme.foreground)
                        .underline()
                    + Text(" delete signed, C2PA verified photos unless you have downloaded them. Would you like to proceed?")
                        .foregroundStyle(Theme.mutedForeground))
                    .textStyle(DesignTokens.TextStyles.body)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage {
                    Text(errorMessage)
                        .textStyle(DesignTokens.TextStyles.label)
                        .foregroundStyle(Theme.destructive)
                }

                HStack(spacing: DesignTokens.Space.s3) {
                    SecondaryButton(title: "No", isEnabled: !isDeleting) {
                        dismiss()
                    }
                    CTAButton(title: isDeleting ? "Deleting…" : "Yes", role: .destructive, isEnabled: !isDeleting) {
                        deleteAccount()
                    }
                }
            }
            .padding(DesignTokens.Space.s6)
            .padding(.top, DesignTokens.Space.s4)
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.background)
        // Swiping away mid-delete wouldn't stop it, only hide whether it
        // worked.
        .interactiveDismissDisabled(isDeleting)
    }

    /// Yes → confirm with Apple (Face ID) → delete. The Apple step is what
    /// lets the backend unlink the app from the user's Apple ID; see
    /// `AppleReauthorization`.
    private func deleteAccount() {
        errorMessage = nil
        isDeleting = true
        Task {
            defer { isDeleting = false }
            let code: String
            do {
                code = try await reauthorization.requestAuthorizationCode()
            } catch let error as ASAuthorizationError where error.code == .canceled {
                // Backing out of the Apple prompt is a "no", not a failure.
                return
            } catch {
                errorMessage = "Couldn't confirm with Apple — please try again."
                Log.settings.error("Apple re-authorization failed: \(error, privacy: .public)")
                return
            }
            do {
                try await appState.deleteAccount(appleAuthorizationCode: code)
                onDeleted()
            } catch {
                errorMessage = switch UserProfileRepository.deleteAccountRejection(error) {
                case "apple_account_mismatch":
                    "That Apple ID isn't the one this account uses. Please confirm with the Apple ID you signed up with."
                default:
                    "Couldn't delete your account — please try again."
                }
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
