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
                NavigationLink("Developer Tools") {
                    DeveloperToolsView()
                }
                NavigationLink("Feature Flags") {
                    FeatureFlagsView()
                }
                NavigationLink("Flow Triggers") {
                    FlowTriggersView()
                }
                // The living styleguide — every token and brand component,
                // in the same order as the web /styleguide and Android's.
                NavigationLink("Design System Styleguide") {
                    DesignSystemStyleguide()
                        .navigationTitle("Styleguide")
                        .navigationBarTitleDisplayMode(.inline)
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
        .preferredColorScheme(.light)
    }
}

/// The explanatory paragraph at the top of a developer menu page — plain
/// text on the page background rather than inside a grouped row.
struct DevMenuDescription: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Section {
            Text(text)
                .textStyle(DesignTokens.TextStyles.label)
                .foregroundStyle(Theme.mutedForeground)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }
    }
}

#Preview {
    DeveloperMenuView()
        .environment(AppState())
}
