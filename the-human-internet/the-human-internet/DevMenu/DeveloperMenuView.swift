//
//  DeveloperMenuView.swift
//  the-human-internet
//

import SwiftUI

/// Reached by shaking the device while signed in as an admin — see
/// `ShakeDetector`, mounted in `RootView` and gated on `AppState.isAdmin`.
struct DeveloperMenuView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Feature Flags") {
                    FeatureFlagsView()
                }
                NavigationLink("Flow Triggers") {
                    FlowTriggersView()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Developer Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    DeveloperMenuView()
        .environment(AppState())
}
