//
//  PhotoVerificationInfoSheet.swift
//  the-human-internet
//

import SwiftUI

struct PhotoVerificationInfoSheet: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                SheetGrabber()

                Text("About Human Photo Verification")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text("We guarantee this photo was taken by a human, using the camera on their phone.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)

                Text("We do not guarantee that the contents of the photo aren't AI generated — someone could still point their camera at a screen. Closing that gap is on our roadmap.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()
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
        PhotoVerificationInfoSheet()
    }
}
