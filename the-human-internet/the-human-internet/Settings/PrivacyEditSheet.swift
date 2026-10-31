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
        VStack(alignment: .leading, spacing: DesignTokens.Space.s6) {
            SheetGrabber()

            VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
                Text("Privacy")
                    .textStyle(DesignTokens.TextStyles.title)
                    .foregroundStyle(Theme.foreground)
                Text("This setting controls who can see your photos and profile if they gain access to the link.")
                    .textStyle(DesignTokens.TextStyles.body)
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
                ForEach(PrivacyLevel.allCases) { level in
                    RadioRow(title: level.rawValue, subtitle: subtitle(for: level), isSelected: selection == level) {
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
        .fittedSheet()
        .onAppear { selection = appState.user.privacy }
    }

    private func subtitle(for level: PrivacyLevel) -> String {
        switch level {
        case .public_: return "Anyone with the link."
        case .humansOnly: return "Only people with the app."
        }
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
