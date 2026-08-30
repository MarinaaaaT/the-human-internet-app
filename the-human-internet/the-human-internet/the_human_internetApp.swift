//
//  the_human_internetApp.swift
//  the-human-internet
//
//  Created by Marina Tassi on 8/4/26.
//

import NewRelic
import SwiftUI

@main
struct the_human_internetApp: App {
    @State private var appState = AppState()

    init() {
        NewRelic.start(withApplicationToken: "AAdcd235ced05915d9caa235b382234d57ed4514a1-NRMA")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}
