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
            VStack(alignment: .leading, spacing: DesignTokens.Space.s6) {
                SheetGrabber()

                Text("Privacy")
                    .textStyle(DesignTokens.TextStyles.title)
                    .foregroundStyle(Theme.foreground)

                VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
                    ForEach(PrivacyLevel.allCases) { level in
                        RadioRow(title: level.rawValue, isSelected: selection == level) {
                            selection = level
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .textStyle(DesignTokens.TextStyles.label)
                        .foregroundStyle(Theme.destructive)
                }

                PrimaryButton(title: isSaving ? "Saving…" : "Save", isEnabled: !isSaving) {
                    save()
                }
            }
            .padding(DesignTokens.Space.s6)
            .padding(.top, DesignTokens.Space.s4)
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
