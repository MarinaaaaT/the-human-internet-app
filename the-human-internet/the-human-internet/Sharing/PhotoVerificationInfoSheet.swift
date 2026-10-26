//
//  PhotoVerificationInfoSheet.swift
//  the-human-internet
//

import SwiftUI

struct PhotoVerificationInfoSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
            SheetGrabber()

            Text("About human photo verification")
                .textStyle(DesignTokens.TextStyles.title)
                .foregroundStyle(Theme.foreground)

            Group {
                Text("We guarantee this photo was taken by a human, using the camera on their phone.")
                Text("We do not guarantee that the contents of the photo aren't AI generated — someone could still point their camera at a screen. Closing that gap is on our roadmap.")
            }
            .textStyle(DesignTokens.TextStyles.body)
            .foregroundStyle(Theme.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.Space.s6)
        .padding(.top, DesignTokens.Space.s4)
        .fittedSheet()
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        PhotoVerificationInfoSheet()
    }
}
