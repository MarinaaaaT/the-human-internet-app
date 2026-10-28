//
//  DemoAccountTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// The demo account's on-device half: which link opens it, what its photos
/// get drawn over them, and that the in-app verification page can tell its
/// photos apart. Everything else about it is server-side (`demo-session`,
/// `stripe-identity-session`, `users.is_demo`).
struct DemoAccountTests {
    @Test func onlyTheDemoLinkOpensTheDemoAccount() throws {
        #expect(DemoAccount.isEntryLink(try #require(URL(string: "thehumaninternet://demo"))))
        #expect(!DemoAccount.isEntryLink(try #require(URL(string: "thehumaninternet://photo/\(UUID().uuidString.lowercased())"))))
        #expect(!DemoAccount.isEntryLink(try #require(URL(string: "https://demo/"))))
        #expect(!DemoAccount.isEntryLink(try #require(URL(string: "https://the-human-internet.com/demo"))))
    }

    @Test func demoPhotosAlwaysGetDemoDrawnOverThem() {
        let appState = AppState()
        appState.isDemoAccount = true
        appState.isWatermarkEnabled = true
        #expect(appState.provisionalMarks == [.fingerprint, .demo])

        // Photo Fingerprint off takes the fingerprint away, never "DEMO".
        appState.isWatermarkEnabled = false
        #expect(appState.provisionalMarks == [.demo])
    }

    @Test func otherAccountsDrawOnlyTheFingerprint() {
        let appState = AppState()
        #expect(appState.provisionalMarks == [.fingerprint])
        appState.isWatermarkEnabled = false
        #expect(appState.provisionalMarks.isEmpty)
    }

    @Test func signingOutForgetsTheDemoAccount() {
        let appState = AppState()
        appState.isDemoAccount = true
        appState.handleSessionInvalidated()
        #expect(!appState.isDemoAccount)
    }

    @Test func ownerProfileReadsIsDemo() throws {
        let json = #"{"username":"demo account","is_verified":true,"display_name":null,"identity_verified_at":null,"social_links":[],"is_demo":true}"#
        let profile = try JSONDecoder().decode(PhotoOwnerProfile.self, from: Data(json.utf8))
        #expect(profile.isDemo)
    }

    /// An RPC that predates `is_demo` must still decode, as not a demo.
    @Test func ownerProfileWithoutIsDemoIsNotADemo() throws {
        let json = #"{"username":"someone","is_verified":false,"display_name":null,"identity_verified_at":null,"social_links":[]}"#
        let profile = try JSONDecoder().decode(PhotoOwnerProfile.self, from: Data(json.utf8))
        #expect(!profile.isDemo)
    }

    @Test func demoWatermarkIsDrawnAtAnySize() {
        let image = DemoWatermark.overlayImage(size: CGSize(width: 300, height: 400))
        #expect(image.size == CGSize(width: 300, height: 400))
    }
}
