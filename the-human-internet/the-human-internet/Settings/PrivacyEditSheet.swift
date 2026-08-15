//
//  PrivacyEditSheet.swift
//  the-human-internet
//

import SwiftUI

struct PrivacyEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PrivacyLevel = .public_
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                SheetGrabber()

                Text("Privacy")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(PrivacyLevel.allCases) { level in
                        RadioRow(title: level.rawValue, isSelected: selection == level) {
                            selection = level
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }

                PrimaryButton(title: isSaving ? "Saving…" : "Save", isEnabled: !isSaving) {
                    save()
                }
            }
            .padding(24)
            .padding(.top, 16)
        }
        .presentationDetents([.fraction(0.4)])
        .presentationBackground(Theme.background)
        .onAppear { selection = appState.user.privacy }
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        var updated = appState.user
        updated.privacy = selection

        Task {
            defer { isSaving = false }
            do {
                try await UserProfileRepository.upsert(updated)
                appState.user = updated
                dismiss()
            } catch {
                errorMessage = "Couldn't save — please try again."
                Log.settings.error("Privacy update failed: \(error, privacy: .public)")
            }
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        PrivacyEditSheet()
            .environment(AppState())
    }
}
