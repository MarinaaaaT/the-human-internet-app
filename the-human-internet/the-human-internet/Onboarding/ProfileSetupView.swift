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

    private let iconOptions = ["person.fill", "pawprint.fill", "star.fill", "flame.fill", "leaf.fill", "moon.fill"]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set up profile")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("The information below may be visible to the public. It can be changed later.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Username")
                    HITextField(placeholder: "Your Username", text: $username)
                }

                VStack(alignment: .leading, spacing: 12) {
                    FieldLabel(text: "Profile Icon")
                    HStack(spacing: 12) {
                        ForEach(iconOptions.indices, id: \.self) { index in
                            Button {
                                selectedIcon = index
                            } label: {
                                Image(systemName: iconOptions[index])
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.surface)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle().stroke(selectedIcon == index ? Theme.accentBlue : .clear, lineWidth: 2)
                                    )
                            }
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
            .padding(24)
            .padding(.top, 24)
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
