//
//  DeveloperToolsTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// "Skip C2PA verification" uploads photos with no provenance claim at all,
/// so the one thing that must hold is that it can never apply to a
/// non-admin — even on a device where an admin left it switched on.
///
/// Serialized because the preference is stored in `UserDefaults.standard`,
/// which every `AppState` in the test host shares.
@Suite(.serialized)
struct DeveloperToolsTests {
    @Test func skippingC2PASigningRequiresAnAdmin() {
        let appState = AppState()
        let original = appState.skipC2PASigningPreference
        defer { appState.skipC2PASigningPreference = original }

        appState.skipC2PASigningPreference = true

        appState.isAdmin = false
        #expect(!appState.isC2PASigningSkipped)

        appState.isAdmin = true
        #expect(appState.isC2PASigningSkipped)
    }

    @Test func c2paSigningIsNotSkippedByDefault() {
        let appState = AppState()
        let original = appState.skipC2PASigningPreference
        defer { appState.skipC2PASigningPreference = original }

        appState.skipC2PASigningPreference = false
        appState.isAdmin = true
        #expect(!appState.isC2PASigningSkipped)
    }

    /// Per-device, so it has to outlive the `AppState` that set it — the
    /// next launch builds a fresh one.
    @Test func thePreferencePersistsAcrossLaunches() {
        let first = AppState()
        let original = first.skipC2PASigningPreference
        defer { first.skipC2PASigningPreference = original }

        first.skipC2PASigningPreference = true
        #expect(AppState().skipC2PASigningPreference)

        first.skipC2PASigningPreference = false
        #expect(!AppState().skipC2PASigningPreference)
    }
}
