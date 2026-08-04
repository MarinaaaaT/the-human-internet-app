//
//  PreviewAsSheetView.swift
//  the-human-internet
//

import SwiftUI

struct PreviewAsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Audience {
        case fellowHuman
        case unknownLurker
    }

    @State private var selection: Audience = .fellowHuman

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                SheetGrabber()

                Text("Preview as…")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 16) {
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

                PrimaryButton(title: "Continue") { dismiss() }
            }
            .padding(24)
            .padding(.top, 16)
        }
        .presentationDetents([.fraction(0.4)])
        .presentationBackground(Theme.background)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        PreviewAsSheetView()
    }
}
