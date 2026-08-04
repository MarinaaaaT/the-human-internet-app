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
        .tint(Theme.accentBlue)
        .toolbarBackground(Theme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
}
