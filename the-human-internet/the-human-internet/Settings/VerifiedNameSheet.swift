//
//  VerifiedNameSheet.swift
//  the-human-internet
//

import SwiftUI

/// Profile settings → Full name's info sheet: where the name came from, and
/// exactly how a viewer will see it.
///
/// The name is **shown, not entered**. It comes from Stripe Identity's
/// `verified_outputs`, stored by `stripe-identity-webhook` under the service
/// role and guarded by triggers against any client write. The verification
/// page renders it beside "taken by a real, verified human", so a name typed
/// in Settings would be a claim wearing our checkmark — which is exactly
/// what an earlier version of this screen allowed. Photo settings chooses
/// whether it's published; nothing chooses what it says.
struct VerifiedNameSheet: View {
    /// `nil` means Stripe never gave us a name for this account — anyone
    /// verified before the webhook stored it.
    let identity: VerifiedIdentity?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
                SheetGrabber()

                Text("Full name")
                    .textStyle(DesignTokens.TextStyles.title)
                    .foregroundStyle(Theme.foreground)

                if let identity {
                    paragraph("This is the name Stripe verified against your ID, so it can't be edited.")

                    HumanCard(radius: DesignTokens.Radius.md) {
                        HStack(alignment: .top, spacing: DesignTokens.Space.s2) {
                            BrandMark(size: DesignTokens.Space.s4)
                            // Exactly what a viewer sees on the verification
                            // page — same `VerifiedIdentity`, same sentence.
                            Text(identity.statement ?? identity.displayName)
                                .textStyle(identity.statement == nil ? DesignTokens.TextStyles.title : DesignTokens.TextStyles.label)
                                .foregroundStyle(identity.statement == nil ? Theme.foreground : Theme.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }

                    paragraph("Choose whether it shows alongside your photos in Photo settings.")
                } else {
                    paragraph("We don't have a verified name on file for your account. It's captured during identity verification — if yours predates that, it'll appear after your next verification.")
                }

                Spacer()
            }
            .padding(DesignTokens.Space.s6)
            .padding(.top, DesignTokens.Space.s4)
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.background)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .textStyle(DesignTokens.TextStyles.body)
            .foregroundStyle(Theme.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        VerifiedNameSheet(identity: VerifiedIdentity(rawName: "MARINA TASSI", verifiedAt: .now))
    }
}
