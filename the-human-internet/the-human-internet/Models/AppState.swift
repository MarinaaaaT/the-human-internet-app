//
//  AppState.swift
//  the-human-internet
//

import SwiftUI
import Observation

@Observable
final class AppState {
    var isOnboarded = false
    var user = HumanUser()
    var photos: [VerifiedPhoto] = []
    var hasSeenFirstPhotoCongrats = false
}
