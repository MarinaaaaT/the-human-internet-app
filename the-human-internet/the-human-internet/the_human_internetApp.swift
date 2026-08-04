//
//  the_human_internetApp.swift
//  the-human-internet
//
//  Created by Marina Tassi on 8/4/26.
//

import SwiftUI

@main
struct the_human_internetApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}
