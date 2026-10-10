//
//  PreviewAsSheetView.swift
//  the-human-internet
//

import SwiftUI

enum PreviewAudience {
    case fellowHuman
    case unknownLurker
}

/// Doesn't dismiss or present anything itself — reports the chosen audience
/// via `onContinue` and lets the caller (`PhotoDetailView`) sequence the
/// sheet dismiss and the actual preview presentation.
struct PreviewAsSheetView: View {
    let onContinue: (PreviewAudience) -> Void

    @State private var selection: PreviewAudience = .fellowHuman

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DesignTokens.Space.s6) {
                SheetGrabber()

                Text("Preview as…")
                    .textStyle(DesignTokens.TextStyles.title)
                    .foregroundStyle(Theme.foreground)

                VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
                    RadioRow(
                        title: "A fellow human",
                        subtitle: "Opens in app",
                        isSelected: selection == .fellowHuman
                    ) { selection = .fellowHuman }

                    RadioRow(
                        title: "An unknown internet lurker",
                        subtitle: "Opens in webview",
                        isSelected: selection == .unknownLurker
                    ) { selection = .unknownLurker }
                }

                PrimaryButton(title: "Continue") { onContinue(selection) }
            }
            .padding(DesignTokens.Space.s6)
            .padding(.top, DesignTokens.Space.s4)
        }
        .presentationDetents([.fraction(0.4)])
        .presentationBackground(Theme.background)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        PreviewAsSheetView(onContinue: { _ in })
    }
}
