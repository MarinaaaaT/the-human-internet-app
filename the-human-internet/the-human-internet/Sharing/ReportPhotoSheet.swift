//
//  ReportPhotoSheet.swift
//  the-human-internet
//

import SwiftUI

/// Reports a photo someone else took, from the in-app verification page.
/// App Review guideline 1.2 asks any app showing other people's content for
/// a way to report it. Reports land in `photo_reports` and are reviewed by
/// hand; the owner is never told who reported them.
struct ReportPhotoSheet: View {
    let photoID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var reason: PhotoReportReason?
    @State private var isSending = false
    @State private var isSent = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s6) {
            SheetGrabber()

            if isSent {
                sent
            } else {
                form
            }
        }
        .padding(DesignTokens.Space.s6)
        .padding(.top, DesignTokens.Space.s4)
        .fittedSheet()
    }

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
            Text("Report this photo")
                .textStyle(DesignTokens.TextStyles.title)
                .foregroundStyle(Theme.foreground)
            Text("Tell us what's wrong. Whoever took it won't know it was you.")
                .textStyle(DesignTokens.TextStyles.body)
                .foregroundStyle(Theme.mutedForeground)
        }

        VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
            ForEach(PhotoReportReason.allCases) { option in
                RadioRow(title: option.title, subtitle: option.subtitle, isSelected: reason == option) {
                    reason = option
                }
            }
        }

        if let error {
            Text(error)
                .textStyle(DesignTokens.TextStyles.label)
                .foregroundStyle(Theme.destructive)
        }

        PrimaryButton(title: isSending ? "Sending…" : "Send report", isEnabled: reason != nil && !isSending) {
            Task { await send() }
        }
    }

    @ViewBuilder
    private var sent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
            Text("Thanks for telling us.")
                .textStyle(DesignTokens.TextStyles.title)
                .foregroundStyle(Theme.foreground)
            Text("We'll take a look and remove it if it shouldn't be here.")
                .textStyle(DesignTokens.TextStyles.body)
                .foregroundStyle(Theme.mutedForeground)
        }

        PrimaryButton(title: "Done") { dismiss() }
    }

    private func send() async {
        guard let reason, !isSending else { return }
        isSending = true
        error = nil
        do {
            try await PhotoRepository.report(photoID: photoID, reason: reason)
            isSent = true
            AccessibilityNotification.Announcement("Report sent.").post()
        } catch {
            Log.photos.error("Report failed for \(photoID, privacy: .public): \(error, privacy: .public)")
            self.error = "Couldn't send your report. Please try again."
        }
        isSending = false
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ReportPhotoSheet(photoID: UUID())
    }
}
