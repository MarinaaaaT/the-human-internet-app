//
//  ShareIntentTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// Pins the composer URLs the Reddit and X icons open.
///
/// These are the *link-first* destinations: nothing but the verification
/// link changes hands, and the picture the reader sees comes from the
/// website's Open Graph card. So the thing that must never break is that
/// the link travelling inside the intent is the public https one — a deep
/// link, or a mangled percent-encoding, silently produces a post nobody
/// can open, and it's already published by the time anyone notices.
struct ShareIntentTests {
    private func makePhoto(shortCode: String = "aB3xK9mP") -> VerifiedPhoto {
        VerifiedPhoto(id: UUID(), userID: UUID(), capturedAt: .now, shortCode: shortCode)
    }

    private func queryItems(of url: URL) throws -> [String: String] {
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    /// Every query value joined — "the text this intent will put in front of
    /// the user", regardless of which parameter each platform carries it in.
    private func allQueryText(of url: URL) throws -> String {
        try queryItems(of: url).values.joined(separator: " ")
    }

    // MARK: - Web composers

    @Test func redditOpensItsSubmitPageAsALinkPost() throws {
        let photo = makePhoto()
        let url = try #require(ShareIntent.reddit.composerURL(for: photo))

        #expect(url.scheme == "https")
        #expect(url.host() == "www.reddit.com")
        #expect(url.path() == "/submit")

        let query = try queryItems(of: url)
        // A link post, not a picture post — the form that renders the card.
        #expect(query["url"] == photo.verificationURL.absoluteString)
        // The link and nothing else. Reddit's own title field has a good
        // placeholder, and anything seeded there would have to be deleted
        // before the user could write their own.
        #expect(query["title"] == nil)
        #expect(query.count == 1)
    }

    @Test func xPutsTheWholePostInTextWithNoSeparateURL() throws {
        let photo = makePhoto()
        let url = try #require(ShareIntent.x.composerURL(for: photo))

        #expect(url.scheme == "https")
        #expect(url.host() == "x.com")
        #expect(url.path() == "/intent/post")

        let query = try queryItems(of: url)
        let text = try #require(query["text"])
        #expect(text == ShareIntent.caption(for: photo))
        #expect(text.contains(photo.verificationURL.absoluteString))

        // X appends `url` to the body, so passing it alongside a caption
        // that already contains the link would post the link twice.
        #expect(query["url"] == nil)
    }

    // MARK: - The app-scheme hop
    //
    // Tried before the web composer, because an https intent doesn't
    // reliably hand off to the platform's app — X actively redirects its
    // web intent out to the browser, which is where the user usually isn't
    // signed in.

    @Test func xOpensTheAppSchemeWithTheSameCaption() throws {
        let photo = makePhoto()
        let url = try #require(ShareIntent.x.appURL(for: photo))

        // The X app still registers the legacy `twitter://` scheme.
        #expect(url.scheme == "twitter")
        #expect(url.host() == "post")

        // One `message` parameter carrying the whole post — the app scheme
        // has no separate `url` parameter, which is exactly why the caption
        // embeds the link rather than relying on one.
        #expect(try queryItems(of: url)["message"] == ShareIntent.caption(for: photo))
    }

    @Test func redditHasNoAppSchemeAndReliesOnItsUniversalLink() {
        // Reddit publishes no documented compose deep link, and its
        // universal link already opens the app for `reddit.com/submit`.
        // Pinned so a future guess at one is a deliberate change.
        #expect(ShareIntent.reddit.appURL(for: makePhoto()) == nil)
    }

    @Test func everyIntentHasAWebComposerToFallBackOn() {
        // The app scheme is speculative — `UIApplication.open` reports
        // whether anything handled it. If a destination had no web URL to
        // fall back to, an uninstalled app would be a dead tap.
        for intent in [ShareIntent.reddit, ShareIntent.x] {
            #expect(intent.composerURL(for: makePhoto()) != nil)
        }
    }

    // MARK: - Contracts every path shares

    @Test func theCaptionIsAPromptAndCarriesTheLink() {
        let photo = makePhoto(shortCode: "aB3xK9mP")
        let caption = ShareIntent.caption(for: photo)

        // The parenthetical exists to be deleted and replaced; what has to
        // survive that edit is the link.
        #expect(caption.hasPrefix("(Add your caption here.)"))
        #expect(caption.hasSuffix("https://the-human-internet.com/aB3xK9mP"))
    }

    @Test(arguments: [ShareIntent.reddit, ShareIntent.x])
    func everyIntentCarriesThePublicLinkNotTheDeepLink(intent: ShareIntent) throws {
        let photo = makePhoto()

        for url in [intent.composerURL(for: photo), intent.appURL(for: photo)].compactMap({ $0 }) {
            let text = try allQueryText(of: url)
            // The same contract `VerifiedPhotoLinkTests` pins for the copied
            // link: it has to resolve for someone who doesn't have the app.
            #expect(text.contains(photo.verificationURL.absoluteString))
            #expect(!text.contains("thehumaninternet://"))
            #expect(!text.contains(photo.verificationDeepLink))
        }
    }

    @Test(arguments: [ShareIntent.reddit, ShareIntent.x])
    func everyWebComposerIsPlainHTTPSSoItNeedsNoQueriedURLScheme(intent: ShareIntent) throws {
        let url = try #require(intent.composerURL(for: makePhoto()))
        // The web fallback must be https: a custom scheme there would need
        // an `LSApplicationQueriesSchemes` entry and would dead-end for
        // anyone without the app. The app-scheme hop above is the one
        // allowed to use a custom scheme, and it's opened speculatively.
        #expect(url.scheme == "https")
    }

    @Test(arguments: [ShareIntent.reddit, ShareIntent.x])
    func theNestedLinkSurvivesPercentEncoding(intent: ShareIntent) throws {
        let photo = makePhoto(shortCode: "aB3xK9mP")

        for url in [intent.composerURL(for: photo), intent.appURL(for: photo)].compactMap({ $0 }) {
            // The link's own `:` and `/` have to be escaped inside the
            // query, or the platform reads a truncated URL.
            #expect(url.absoluteString.contains("https%3A%2F%2Fthe-human-internet.com%2FaB3xK9mP"))
            // ...and decode back to exactly the link we meant to share.
            #expect(try allQueryText(of: url).contains("https://the-human-internet.com/aB3xK9mP"))
        }
    }
}
