//
//  VerificationPageCustomizationTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// Pins the app's half of the verification-page customization contract —
/// the `show_identity` and `social_links` columns on `public.users`, and
/// what `get_verification_photo()` will and won't publish from them.
///
/// The name is deliberately absent from `HumanUser`. It used to live here as
/// `display_first_name` / `display_last_name`, typed by the user — and the
/// verification page renders the name beside "taken by a real, verified
/// human", so that was a self-authored claim wearing our checkmark. It now
/// comes from `users.verified_first_name` / `verified_last_name`, written
/// only by stripe-identity-webhook and guarded by triggers, and read through
/// the narrow `UserProfileRepository.fetchVerifiedName`. The encoding test
/// below is what keeps a name from creeping back onto the upsert.
///
/// The handle rules matter more than they look. `users_social_links_check`
/// rejects the *whole row*, and `HumanUser` round-trips through one upsert,
/// so a handle the database refuses fails a save that is also carrying the
/// username and the privacy setting. `VerificationPageSheet` normalises and
/// validates before it ever gets there; these tests are what keep the two
/// halves of that rule in step.
struct VerificationPageCustomizationTests {

    // MARK: - Handles

    /// The `@` is what people type; the database's regex doesn't allow it,
    /// and the website's per-platform base URLs don't want it either.
    @Test(arguments: [
        ("@marina", "marina"),
        ("  marina  ", "marina"),
        ("@@marina", "marina"),
        (" @marina\n", "marina"),
        ("marina", "marina"),
    ])
    func normalizeStripsWhatPeopleActuallyType(input: String, expected: String) {
        #expect(SocialLink.normalize(handle: input) == expected)
    }

    /// Mirrors `^[A-Za-z0-9._-]{1,64}$` in `is_valid_social_links()`.
    @Test(arguments: ["marina", "m", "a.b_c-d", "MixedCase123", String(repeating: "a", count: 64)])
    func acceptsHandlesTheDatabaseAccepts(handle: String) {
        #expect(SocialLink.isValid(handle: handle))
    }

    /// Each of these would come back as a Postgres CHECK violation on a
    /// save that also carries the user's username — so they have to be
    /// caught in the sheet, not at the server.
    @Test(arguments: [
        "",                                   // an abandoned empty row
        "@marina",                            // un-normalised
        "marina smith",                       // space
        "marina/smith",                       // path separator
        "marina?x=1",                         // query
        "https://example.com/marina",         // a whole URL
        "javascript:alert(1)",                // the reason handles are bare
        "марина",                             // non-ASCII
    ])
    func rejectsHandlesTheDatabaseRejects(handle: String) {
        #expect(!SocialLink.isValid(handle: handle))
    }

    @Test func rejectsAHandleOneCharacterOverTheLimit() {
        #expect(!SocialLink.isValid(handle: String(repeating: "a", count: SocialLink.maxHandleLength + 1)))
    }

    // MARK: - Decoding

    /// Shaped like a real PostgREST row. `verified_first_name` /
    /// `verified_last_name` are present exactly because `HumanUser` must
    /// *ignore* them — they're read separately, never round-tripped.
    private func userRowJSON(socialLinks: String, showIdentity: Bool = true) -> Data {
        Data("""
        {
          "id": "2e9232a7-0f69-4bec-af8c-0455d3af107d",
          "username": "Marina",
          "profile_icon_index": 0,
          "phone_number": "",
          "privacy": "Public",
          "verification_status": "verified",
          "onboarding_step": "completed",
          "verified_first_name": "Marina",
          "verified_last_name": "Tassi",
          "show_identity": \(showIdentity),
          "social_links": \(socialLinks)
        }
        """.utf8)
    }

    @Test func decodesTheCustomizationColumns() throws {
        let json = userRowJSON(
            socialLinks: #"[{"platform":"instagram","handle":"marina"},{"platform":"x","handle":"marina_t"}]"#
        )
        let user = try JSONDecoder().decode(HumanUser.self, from: json)

        #expect(user.showIdentity)
        #expect(user.socialLinks.items.map(\.platform) == [.instagram, .x])
        #expect(user.socialLinks.items.map(\.handle) == ["marina", "marina_t"])
    }

    /// The whole reason `SocialLinks` has a hand-written decoder. A platform
    /// added to the database's whitelist tomorrow lands on every build
    /// installed today, and this array is decoded as part of the user row in
    /// `AppState.hydrate` — immediately after Sign in with Apple. Throwing
    /// here wouldn't cost a link, it would cost the whole session.
    @Test func unknownPlatformDropsTheEntryRatherThanFailingSignIn() throws {
        let json = userRowJSON(
            socialLinks: #"[{"platform":"instagram","handle":"marina"},{"platform":"bluesky","handle":"marina"}]"#
        )
        let user = try JSONDecoder().decode(HumanUser.self, from: json)

        #expect(user.socialLinks.items.map(\.platform) == [.instagram])
        // The rest of the row still has to survive intact.
        #expect(user.username == "Marina")
        #expect(user.showIdentity)
    }

    @Test func malformedEntriesDontTakeTheRowDownEither() throws {
        let json = userRowJSON(socialLinks: #"["nonsense", {"handle":"marina"}, 7]"#)
        let user = try JSONDecoder().decode(HumanUser.self, from: json)

        #expect(user.socialLinks.items.isEmpty)
        #expect(user.username == "Marina")
    }

    @Test func emptySocialLinksDecodeToAnEmptyList() throws {
        let user = try JSONDecoder().decode(HumanUser.self, from: userRowJSON(socialLinks: "[]"))
        #expect(user.socialLinks.items.isEmpty)
    }

    // MARK: - Encoding

    /// The upsert has to name the columns the way Postgres does, and send
    /// `social_links` as a bare array of `{platform, handle}` objects —
    /// `is_valid_social_links()` rejects any extra key, `id` included, and
    /// `SocialLink.id` is a client-side row identity that must not ship.
    @Test func encodesTheColumnNamesAndShapeTheDatabaseExpects() throws {
        var user = HumanUser(id: UUID())
        user.showIdentity = true
        user.socialLinks = SocialLinks([SocialLink(platform: .github, handle: "marina")])

        let encoded = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(user)) as? [String: Any]

        #expect(encoded?["show_identity"] as? Bool == true)

        let links = try #require(encoded?["social_links"] as? [[String: Any]])
        #expect(links.count == 1)
        #expect(links[0]["platform"] as? String == "github")
        #expect(links[0]["handle"] as? String == "marina")
        #expect(links[0].keys.sorted() == ["handle", "platform"])
    }

    /// Every case here has to exist in `is_valid_social_links()`'s `in (…)`
    /// list and in `SOCIAL_PLATFORMS` on the website. The raw values are the
    /// contract; the display names are ours alone.
    @Test func everyPlatformRawValueIsOneTheDatabaseWhitelists() {
        let whitelisted: Set<String> = [
            "instagram", "x", "tiktok", "youtube",
            "linkedin", "github", "reddit", "facebook",
        ]
        #expect(Set(SocialPlatform.allCases.map(\.rawValue)) == whitelisted)
    }

    // MARK: - The name never rides on the upsert

    /// The regression guard for the reason this file exists.
    ///
    /// `HumanUser` round-trips through one whole-row upsert, so any name
    /// field on it would be posted back by the client on every profile save
    /// — and a client-supplied name is exactly what must never reach the
    /// verification page. The `prevent_self_verified_name_change` trigger
    /// would revert it, but silently, so the app would believe it had
    /// written something it hadn't.
    ///
    /// If this fails, someone has put a name back on `HumanUser`. Read it
    /// separately instead (`UserProfileRepository.fetchVerifiedName`).
    @Test func theEncodedRowCarriesNoNameFieldAtAll() throws {
        var user = HumanUser(id: UUID())
        user.showIdentity = true
        user.username = "Marina"

        let encoded = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(user)) as? [String: Any]
        )

        for key in encoded.keys {
            #expect(
                !key.contains("name") || key == "username",
                "HumanUser encoded an unexpected name-ish column: \(key)"
            )
        }
        #expect(encoded["display_first_name"] == nil)
        #expect(encoded["display_last_name"] == nil)
        #expect(encoded["verified_first_name"] == nil)
        #expect(encoded["verified_last_name"] == nil)
    }

    /// Decoding a row that carries the verified name must not surface it on
    /// the model — otherwise it would be one refactor away from being
    /// encoded again.
    @Test func decodingIgnoresTheVerifiedNameColumns() throws {
        let user = try JSONDecoder().decode(HumanUser.self, from: userRowJSON(socialLinks: "[]"))
        let encoded = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(user)) as? [String: Any]
        )
        #expect(encoded["verified_first_name"] == nil)
        #expect(encoded["verified_last_name"] == nil)
    }
}
