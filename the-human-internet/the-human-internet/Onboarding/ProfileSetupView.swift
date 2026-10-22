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
    /// Stands in for "the keyboard is up": the username field is the only
    /// thing on this screen that raises it.
    @FocusState private var isEditingUsername: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Outline symbols, per the icon rule. Stored by index
    /// (`profileIconIndex`), so the order must not change.
    private let iconOptions = ["person", "pawprint", "star", "flame", "leaf", "moon"]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            // The form scrolls and Next rides above it in a bottom inset,
            // rather than all of it sharing one VStack with a Spacer. That
            // VStack didn't fit above the keyboard, so SwiftUI squeezed it:
            // the subcopy truncated and Next lost its bottom padding, ending
            // up flush against the keyboard.
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Space.s8) {
                    VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
                        Text("Set up profile")
                            .textStyle(DesignTokens.TextStyles.h2)
                            .foregroundStyle(Theme.foreground)
                        // Dropped while typing, to give the keyboard room.
                        if !isEditingUsername {
                            Text("This information is public. It can be changed later.")
                                .textStyle(DesignTokens.TextStyles.body)
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
                        FieldLabel(text: "Username")
                        HITextField(placeholder: "Your username", text: $username)
                            .focused($isEditingUsername)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignTokens.Space.s6)
                .padding(.top, DesignTokens.Space.s6)
                // The subcopy fades as the keyboard rises, and the fields
                // close the gap with it rather than jumping.
                .animation(reduceMotion ? nil : .brandBase, value: isEditingUsername)
            }
            .scrollBounceBehavior(.basedOnSize)
            // An inset sits on the keyboard's edge whenever it's up, so the
            // padding below Next is kept clear above the keyboard too.
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Next", isEnabled: !username.trimmingCharacters(in: .whitespaces).isEmpty) {
                    appState.user.username = username
                    appState.user.profileIconIndex = selectedIcon
                    onNext()
                }
                .padding(DesignTokens.Space.s6)
                .background(Theme.background)
            }
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
