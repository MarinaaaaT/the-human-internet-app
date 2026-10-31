//
//  ShareInstructionsSheetView.swift
//  the-human-internet
//

import SwiftUI

/// Shown right before the native share sheet opens. No social platform
/// reliably accepts a caption from a third-party app (Facebook and
/// Instagram flatly never do, by platform policy), so instead of trying to
/// inject one, this tells the user the verification link is already on
/// their clipboard, ready to paste into whatever caption field they land on.
struct ShareInstructionsSheetView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
            SheetGrabber()

            Text("Before you share")
                .textStyle(DesignTokens.TextStyles.title)
                .foregroundStyle(Theme.foreground)

            Text("We've copied the verification link to your clipboard. Paste it into your caption alongside the photo, so anyone who sees it can verify it's real.")
                .textStyle(DesignTokens.TextStyles.body)
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: "Continue") { onContinue() }
                .padding(.top, DesignTokens.Space.s2)
        }
        .padding(DesignTokens.Space.s6)
        .padding(.top, DesignTokens.Space.s4)
        .fittedSheet()
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ShareInstructionsSheetView(onContinue: {})
    }
}
