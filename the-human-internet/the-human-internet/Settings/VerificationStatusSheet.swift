//
//  VerificationStatusSheet.swift
//  the-human-internet
//

import SwiftUI

struct VerificationStatusSheet: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                SheetGrabber()

                Text("Verification Status")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text("While it is in progress, content you share will clearly state that you are an unverified human.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)

                Text("If your verification status fails and is not resubmitted within 14 days, you will be removed from the human internet.")
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
        VerificationStatusSheet()
    }
}
