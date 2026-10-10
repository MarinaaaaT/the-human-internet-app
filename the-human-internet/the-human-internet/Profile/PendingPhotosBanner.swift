//
//  PendingPhotosBanner.swift
//  the-human-internet
//

import SwiftUI

/// Shown at the top of the Profile tab whenever a photo is still being
/// signed/uploaded or has failed. Reads `AppState`'s sets directly — no
/// local state needed, since `AppState` is `@Observable` and already
/// updates live as `PhotoUploadQueue.drive()` mutates them.
struct PendingPhotosBanner: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
            if !appState.processingPhotoIDs.isEmpty {
                row(label: "Verifying", value: "\(countText(appState.processingPhotoIDs.count)) still being verified.")
            }
            if !appState.failedPhotoIDs.isEmpty {
                // Ticks once a second only so the "Tap to try again" prompt
                // appears the moment `PhotoUploadQueue`'s cooldown lapses.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let canRetry = PhotoUploadQueue.manualRetryAvailableAt == nil
                    let failed = "\(countText(appState.failedPhotoIDs.count)) failed to verify or save."
                    Button {
                        retryAllFailed()
                    } label: {
                        row(label: "Not saved yet", value: canRetry ? "\(failed) Tap to try again." : failed)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRetry)
                }
            }
        }
    }

    private func row(label: String, value: String) -> some View {
        HumanCard(radius: DesignTokens.Radius.md, padding: DesignTokens.Space.s3) {
            LabelValue(label: label, value: value)
                .multilineTextAlignment(.leading)
        }
    }

    private func countText(_ count: Int) -> String {
        "\(count) photo\(count == 1 ? "" : "s")"
    }

    private func retryAllFailed() {
        PhotoUploadQueue.retry(photoIDs: appState.failedPhotoIDs, appState: appState)
    }
}

#Preview {
    PendingPhotosBanner()
        .environment(AppState())
        .padding()
        .background(Theme.background)
}
