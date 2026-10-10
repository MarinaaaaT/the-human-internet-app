//
//  EditUsernameSheet.swift
//  the-human-internet
//

import SwiftUI

struct EditUsernameSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DesignTokens.Space.s6) {
                SheetGrabber()

                Text("Edit username")
                    .textStyle(DesignTokens.TextStyles.title)
                    .foregroundStyle(Theme.foreground)

                HITextField(placeholder: "New username here", text: $username)

                if let errorMessage {
                    Text(errorMessage)
                        .textStyle(DesignTokens.TextStyles.label)
                        .foregroundStyle(Theme.destructive)
                }

                PrimaryButton(
                    title: isSaving ? "Saving…" : "Save",
                    isEnabled: !isSaving && !username.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    save()
                }
            }
            .padding(DesignTokens.Space.s6)
            .padding(.top, DesignTokens.Space.s4)
        }
        .presentationDetents([.fraction(0.35)])
        .presentationBackground(Theme.background)
        .onAppear { username = appState.user.username }
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        var updated = appState.user
        updated.username = username

        Task {
            defer { isSaving = false }
            do {
                try await UserProfileRepository.upsert(updated)
                appState.user = updated
                dismiss()
            } catch {
                errorMessage = UserProfileRepository.isUsernameConflict(error)
                    ? "That username is already taken."
                    : "Couldn't save — please try again."
                Log.settings.error("Username update failed: \(error, privacy: .public)")
            }
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        EditUsernameSheet()
            .environment(AppState())
    }
}
