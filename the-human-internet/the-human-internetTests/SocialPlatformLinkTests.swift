//
//  SocialPlatformLinkTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// Pins `SocialPlatform.profileURL(handle:)` and `displayHandle(_:)` against
/// `SOCIAL_PLATFORMS` in the website's `src/lib/photos/socialLinks.ts`.
///
/// The two exist because the same social handles are now rendered twice — on
/// the public verification page and on the in-app one — and a handle that
/// links somewhere different depending on which page you opened is a bug
/// nobody would report, because each page looks right on its own.
///
/// Nothing makes them fail to compile when they drift, which is the same
/// exposure `HumanUserDecodingTests` covers for the enums. The expected
/// strings below are transcribed from that TypeScript table; if you change
/// one here, change it there in the same breath.
/// One row of the website's table, transcribed. A named type rather than a
/// tuple so `@Test(arguments:)` takes a single parameter — tuple
/// destructuring past two elements isn't something to rely on.
struct PlatformExpectation: Sendable {
    let platform: SocialPlatform
    let url: String
    let display: String
}

/// Every platform, its URL, and how the handle reads — character for
/// character what `socialLinks.ts` produces for the handle "marina".
private let expectations: [PlatformExpectation] = [
    .init(platform: .instagram, url: "https://www.instagram.com/marina/", display: "@marina"),
    .init(platform: .x, url: "https://x.com/marina", display: "@marina"),
    .init(platform: .tiktok, url: "https://www.tiktok.com/@marina", display: "@marina"),
    .init(platform: .youtube, url: "https://www.youtube.com/@marina", display: "@marina"),
    .init(platform: .linkedin, url: "https://www.linkedin.com/in/marina", display: "marina"),
    .init(platform: .github, url: "https://github.com/marina", display: "marina"),
    .init(platform: .reddit, url: "https://www.reddit.com/user/marina", display: "u/marina"),
    .init(platform: .facebook, url: "https://www.facebook.com/marina", display: "marina"),
]

struct SocialPlatformLinkTests {
    @Test(arguments: expectations)
    func matchesTheWebsitesTable(expected: PlatformExpectation) {
        #expect(expected.platform.profileURL(handle: "marina")?.absoluteString == expected.url)
        #expect(expected.platform.displayHandle("marina") == expected.display)
    }

    /// If a platform is added to the enum without a row above, this fails —
    /// which is the point. The website table has to grow at the same time.
    @Test func everyPlatformIsCovered() {
        #expect(Set(expectations.map(\.platform)) == Set(SocialPlatform.allCases))
    }

    /// The handle is revalidated before it becomes a URL. It has already
    /// passed a Postgres CHECK and the RPC's gating by this point, but this
    /// is the step that turns another user's data into something tappable,
    /// so it costs one `allSatisfy` to not rely on that.
    @Test(arguments: [
        "marina smith",             // space
        "marina/../evil",           // path traversal
        "marina?x=1",               // query
        "https://evil.example.com", // a whole URL
        "javascript:alert(1)",      // the reason this check exists
        "",                         // empty
    ])
    func refusesToBuildAURLFromAnInvalidHandle(handle: String) {
        for platform in SocialPlatform.allCases {
            #expect(platform.profileURL(handle: handle) == nil)
        }
    }

    /// A valid handle must always produce a URL — a `nil` here would silently
    /// flatten a real account to plain text on both pages.
    @Test func everyValidHandleResolves() {
        for platform in SocialPlatform.allCases {
            #expect(platform.profileURL(handle: "a.b_c-1") != nil)
            #expect(platform.profileURL(handle: String(repeating: "a", count: 64)) != nil)
        }
    }
}
