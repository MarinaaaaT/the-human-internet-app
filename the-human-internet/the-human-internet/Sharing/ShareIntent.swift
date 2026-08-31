//
//  ShareIntent.swift
//  the-human-internet
//

import Foundation

/// A destination that takes the verification link *directly*, pre-filled
/// into its own composer, via a plain `https://` intent URL.
///
/// This is the link-first path, and it only became the better option once
/// the website grew an `opengraph-image` route: Reddit and X both render
/// the Open Graph card, so a link post already shows the picture, the
/// username and the verified claim — and it stays tappable through to the
/// proof, which a picture never is.
///
/// Uploading the image to them instead would be strictly worse. Every one
/// of these platforms re-encodes on upload, which strips the C2PA manifest
/// out of the JPEG, leaving a bare picture making a claim it can no longer
/// back. Only the burned-in watermark survives that trip; the hosted copy
/// behind the link is the one that stays verifiable.
///
/// No SDK, no registered application id, and no `LSApplicationQueriesSchemes`
/// entry — these are ordinary https URLs, so they open the platform's own
/// app through its universal link when it's installed, and fall back to the
/// browser when it isn't.
enum ShareIntent {
    case reddit
    case x

    /// Seeds the post body, link included. Written as a prompt rather
    /// than a finished caption: the parenthetical is there to be deleted
    /// and replaced, so what's left is the one part that matters — the
    /// link. Editable before posting either way; this is a starting point,
    /// not a caption put in someone's mouth.
    ///
    /// Only X uses it. Reddit deliberately gets no seeded text at all —
    /// see `composerURL`.
    static func caption(for photo: VerifiedPhoto) -> String {
        "(Add your caption here.) Check this photo is real at \(photo.verificationURL.absoluteString)"
    }

    /// The platform's *own app*, via its custom URL scheme — `nil` where
    /// no such scheme is known.
    ///
    /// Tried before `composerURL`, because an https intent does not
    /// reliably hand off to the app. X in particular actively pushes the
    /// other way: `x.com/intent/post` answers an iPhone user agent with an
    /// `x-safari-https://` redirect, which is the mechanism for forcing a
    /// URL *out* to the browser. Its web intent is a web composer by
    /// design, so on its own it always lands in Safari — where the user is
    /// usually not signed in — rather than the app.
    ///
    /// Opened speculatively rather than checked with `canOpenURL`, which
    /// would require every scheme listed in `LSApplicationQueriesSchemes`.
    /// `UIApplication.open`'s completion reports whether anything handled
    /// it, and the caller falls back to `composerURL` when nothing did —
    /// so an uninstalled app costs a failed open, not a dead tap.
    func appURL(for photo: VerifiedPhoto) -> URL? {
        switch self {
        case .reddit:
            // Reddit has a `reddit://` scheme but no documented compose
            // deep link, and its universal link already opens the app for
            // `reddit.com/submit`. Nothing to gain by guessing at one.
            return nil

        case .x:
            // The X app still registers the legacy `twitter://` scheme.
            // `message` is the entire post — unlike the web intent there's
            // no separate `url` parameter, so the link is appended to the
            // text rather than passed alongside it.
            var components = URLComponents(string: "twitter://post")
            components?.percentEncodedQuery = Self.encodedQuery([
                URLQueryItem(name: "message", value: Self.caption(for: photo))
            ])
            return components?.url
        }
    }

    /// The composer URL for `photo`, or `nil` if it couldn't be built.
    ///
    /// The web fallback, for when the platform's app isn't installed.
    ///
    /// Always carries `verificationURL` — the public link that resolves
    /// signed-out — and never the `thehumaninternet://` deep link, which
    /// would be a dead tap for everyone without the app.
    func composerURL(for photo: VerifiedPhoto) -> URL? {
        let link = photo.verificationURL.absoluteString

        let base: String
        let queryItems: [URLQueryItem]

        switch self {
        case .reddit:
            // Reddit's own submit page, pre-filled as a *link* post — the
            // form that renders the card. The user still chooses the
            // subreddit, and can edit the title before posting.
            base = "https://www.reddit.com/submit"
            // The link and nothing else. No seeded title: Reddit's own
            // title field has a good placeholder, and anything we put
            // there would have to be deleted before the user could write
            // their own. The unfurled card carries the picture.
            queryItems = [URLQueryItem(name: "url", value: link)]
        case .x:
            // `intent/post` is the current spelling of what used to be
            // `intent/tweet`; the older path still redirects here.
            base = "https://x.com/intent/post"
            // Everything in `text`, with no separate `url` parameter: X
            // appends `url` to the body, so passing both would post the
            // link twice now that the caption carries it. X unfurls a link
            // found in the text just the same.
            queryItems = [URLQueryItem(name: "text", value: Self.caption(for: photo))]
        }

        var components = URLComponents(string: base)
        components?.percentEncodedQuery = Self.encodedQuery(queryItems)
        return components?.url
    }

    /// Percent-encodes a query by hand rather than assigning
    /// `URLComponents.queryItems`.
    ///
    /// `queryItems` escapes only what's *illegal* in a query, and `:` and
    /// `/` are both legal there — so it nests the verification URL into
    /// these intents unescaped. That happens to work today, because a
    /// short code is Base58 and so can never contain the `&`, `#` or `?`
    /// that would actually truncate the link. The encoding shouldn't
    /// depend on that staying true, and every platform's own share button
    /// escapes the nested URL too, so this escapes everything outside the
    /// RFC 3986 unreserved set.
    private static func encodedQuery(_ items: [URLQueryItem]) -> String {
        items.compactMap { item -> String? in
            guard let name = item.name.addingPercentEncoding(withAllowedCharacters: unreserved),
                  let value = item.value?.addingPercentEncoding(withAllowedCharacters: unreserved)
            else { return nil }
            return "\(name)=\(value)"
        }
        .joined(separator: "&")
    }

    /// The RFC 3986 unreserved set — the only characters that never need
    /// escaping anywhere in a URL.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}
