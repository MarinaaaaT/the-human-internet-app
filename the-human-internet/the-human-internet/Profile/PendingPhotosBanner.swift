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
        VStack(alignment: .leading, spacing: 8) {
            if !appState.processingPhotoIDs.isEmpty {
                row(
                    text: "\(countText(appState.processingPhotoIDs.count)) still being verified",
                    color: Theme.warning
                )
            }
            if !appState.failedPhotoIDs.isEmpty {
                Button {
                    retryAllFailed()
                } label: {
                    row(
                        text: "\(countText(appState.failedPhotoIDs.count)) failed to verify or save. Click this message to try again.",
                        color: .red
                    )
                }
            }
        }
        .task {
            // Belt-and-suspenders: re-kicks any manifest entry not
            // currently being driven, in case a `Task` above ever dies
            // without going through `drive()`'s own catch block. Not the
            // primary recovery path — a killed/relaunched app already
            // resumes via `AppState.hydrate` regardless of this view.
            while true {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                if let userID = appState.user.id {
                    PhotoUploadQueue.resumePendingUploads(userID: userID, appState: appState)
                }
            }
        }
    }

    private func row(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func countText(_ count: Int) -> String {
        "\(count) photo\(count == 1 ? "" : "s")"
    }

    private func retryAllFailed() {
        for photoID in appState.failedPhotoIDs {
            PhotoUploadQueue.retry(photoID: photoID, appState: appState)
        }
    }
}

#Preview {
    PendingPhotosBanner()
        .environment(AppState())
        .padding()
        .background(Theme.background)
}
