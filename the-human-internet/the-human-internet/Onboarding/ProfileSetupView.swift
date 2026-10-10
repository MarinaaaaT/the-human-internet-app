//
//  ProfileSetupView.swift
//  the-human-internet
//

import SwiftUI

struct ProfileSetupView: View {
    @Environment(AppState.self) private var appState
    var onNext: () -> Void

    @State private var username = ""
    @State private var selectedIcon = 0

    /// Outline symbols, per the icon rule. Stored by index
    /// (`profileIconIndex`), so the order must not change.
    private let iconOptions = ["person", "pawprint", "star", "flame", "leaf", "moon"]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DesignTokens.Space.s8) {
                VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
                    Text("Set up profile")
                        .textStyle(DesignTokens.TextStyles.h2)
                        .foregroundStyle(Theme.foreground)
                    Text("The information below may be visible to the public. It can be changed later.")
                        .textStyle(DesignTokens.TextStyles.body)
                        .foregroundStyle(Theme.mutedForeground)
                }

                VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
                    FieldLabel(text: "Username")
                    HITextField(placeholder: "Your username", text: $username)
                }

                VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
                    FieldLabel(text: "Profile icon")
                    // Six 48pt circles don't fit a small phone in one row.
                    FlowLayout(spacing: DesignTokens.Space.s2) {
                        ForEach(iconOptions.indices, id: \.self) { index in
                            Button {
                                selectedIcon = index
                            } label: {
                                Image(systemName: iconOptions[index])
                                    .symbolStyle(DesignTokens.TextStyles.title)
                                    .ctaIcon()
                                    .overlay(
                                        Circle().stroke(selectedIcon == index ? Theme.foreground : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(iconOptions[index])
                            .accessibilityAddTraits(selectedIcon == index ? .isSelected : [])
                        }
                    }
                }

                Spacer()

                PrimaryButton(title: "Next", isEnabled: !username.trimmingCharacters(in: .whitespaces).isEmpty) {
                    appState.user.username = username
                    appState.user.profileIconIndex = selectedIcon
                    onNext()
                }
            }
            .padding(DesignTokens.Space.s6)
            .padding(.top, DesignTokens.Space.s6)
        }
        .onAppear {
            // Resuming after a previous session — prefill what was already entered.
            username = appState.user.username
            selectedIcon = appState.user.profileIconIndex
        }
    }
}

#Preview {
    NavigationStack {
        ProfileSetupView(onNext: {})
            .environment(AppState())
    }
}
