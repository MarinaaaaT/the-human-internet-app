//
//  PhotoVerificationInfoSheet.swift
//  the-human-internet
//

import SwiftUI

struct PhotoVerificationInfoSheet: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
                SheetGrabber()

                Text("About human photo verification")
                    .textStyle(DesignTokens.TextStyles.title)
                    .foregroundStyle(Theme.foreground)

                Text("We guarantee this photo was taken by a human, using the camera on their phone.")
                    .textStyle(DesignTokens.TextStyles.body)
                    .foregroundStyle(Theme.mutedForeground)

                Text("We do not guarantee that the contents of the photo aren't AI generated — someone could still point their camera at a screen. Closing that gap is on our roadmap.")
                    .textStyle(DesignTokens.TextStyles.body)
                    .foregroundStyle(Theme.mutedForeground)

                Spacer()
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
        PhotoVerificationInfoSheet()
    }
}
