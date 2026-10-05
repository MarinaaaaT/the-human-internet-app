//
//  MainTabView.swift
//  the-human-internet
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                CameraCaptureView()
            }
            .tabItem {
                Image(systemName: "camera.fill")
                Text("Camera")
            }

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Image(systemName: "person.crop.square")
                Text("Profile")
            }
        }
        .tint(Theme.selection)
        .toolbarBackground(Theme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
}
