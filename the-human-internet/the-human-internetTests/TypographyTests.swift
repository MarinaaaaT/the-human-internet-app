//
//  TypographyTests.swift
//  the-human-internetTests
//

import Testing
import SwiftUI
import UIKit

@testable import the_human_internet

/// `Font.custom` with a name iOS doesn't know silently falls back to the
/// system font — so a typo in a PostScript name, or a file missing from
/// `UIAppFonts`, ships as "the font change didn't take" with nothing failing.
struct TypographyTests {
    /// Every weight `Theme.font` can ask Inter Display for must actually be
    /// registered from the bundle.
    @Test(arguments: [Font.Weight.regular, .medium, .semibold, .bold, .black])
    func interDisplayWeightsAreRegistered(weight: Font.Weight) {
        let name = FontFamily.interDisplay.postScriptName(for: weight)
        #expect(UIFont(name: name, size: 12) != nil, "\(name) isn't registered — check UIAppFonts in Info.plist")
    }

    /// The licence-restricted font is fetched only when the server says so,
    /// and never bundled — so a build that can't read the flag must not try.
    @Test func neueFontFallsBackToOff() {
        #expect(FeatureFlagKey.fallbackAudience(for: FeatureFlagKey.neueFont) == .off)
    }

    /// Nothing in the default state may point at Neue Montreal: a fresh
    /// install, signed out, has no access to the files.
    @Test func defaultFamilyIsInterDisplay() {
        #expect(Typography().family == .interDisplay)
    }
}
