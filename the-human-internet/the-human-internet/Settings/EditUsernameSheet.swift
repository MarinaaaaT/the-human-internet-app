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
            VStack(alignment: .leading, spacing: 20) {
                SheetGrabber()

                Text("Edit Username")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                HITextField(placeholder: "New username here", text: $username)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }

                PrimaryButton(
                    title: isSaving ? "Saving…" : "Save",
                    isEnabled: !isSaving && !username.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    save()
                }
            }
            .padding(24)
            .padding(.top, 16)
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
                debugPrint(error)
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
