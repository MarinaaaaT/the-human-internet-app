//
//  VerifiedIdentityTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// Pins the one sentence both verification surfaces make about a person's
/// identity, and the re-casing of the name inside it.
///
/// Stripe reads these names off identity documents, so they arrive shouting
/// — the live value on this project's own account is `JORDAN JAMES` /
/// `FAVA`. Rendering that verbatim beside a verified badge looks like a
/// database dump, so it gets re-cased for display only; the stored value is
/// never touched, and nothing but the webhook can write it anyway.
///
/// `titleCased` mirrors `titleCaseName` in the website's
/// `src/lib/photos/verificationPhoto.ts`. Same inputs, same outputs — the
/// same person must not be spelled two ways on two surfaces.
struct VerifiedIdentityTests {

    // MARK: - Re-casing

    @Test func recasesTheRealVerifiedNameOnThisProjectsAccount() {
        #expect(VerifiedIdentity.titleCased("JORDAN JAMES FAVA") == "Jordan James Fava")
    }

    /// Apostrophes and hyphens are word breaks, so these come out right.
    @Test(arguments: [
        ("O'BRIEN", "O'Brien"),
        ("MARY-JANE WATSON", "Mary-Jane Watson"),
        ("JOSÉ GARCÍA", "José García"),
        ("ANNE-MARIE O'NEILL", "Anne-Marie O'Neill"),
    ])
    func recasesAcrossWordBreaks(raw: String, expected: String) {
        #expect(VerifiedIdentity.titleCased(raw) == expected)
    }

    /// A value carrying any lowercase letter was cased deliberately, and
    /// re-casing it could only make it worse. Left exactly alone.
    @Test(arguments: ["van der Berg", "McDonald", "Jordan James Fava", "de la Cruz"])
    func leavesDeliberatelyCasedNamesAlone(name: String) {
        #expect(VerifiedIdentity.titleCased(name) == name)
    }

    /// The documented limit, pinned so it's a known trade rather than a
    /// surprise: spotting Mc/Mac/O' from the string alone isn't reliable,
    /// and the rule that fixes this would turn "MACEY" into "MacEy".
    @Test func shoutedMcNamesLoseTheirInnerCapital() {
        #expect(VerifiedIdentity.titleCased("MCDONALD") == "Mcdonald")
    }

    @Test func emptyNameSurvives() {
        #expect(VerifiedIdentity.titleCased("") == "")
    }

    // MARK: - The sentence

    private static let verifiedAt = Date(timeIntervalSince1970: 1_788_357_720)  // 2026-09-04 UTC

    @Test func statesTheDateAndTheRecasedName() {
        let identity = VerifiedIdentity(rawName: "JORDAN JAMES FAVA", verifiedAt: Self.verifiedAt)

        let statement = identity.statement
        #expect(statement?.hasPrefix("Identity Last Verified by Stripe on ") == true)
        #expect(statement?.hasSuffix(" proving account owner is Jordan James Fava") == true)
        // Never the stored shouting form.
        #expect(statement?.contains("JORDAN") == false)
    }

    /// Without a date there is no sentence to make — the name is still true,
    /// but "Last Verified on …" would not be. Callers fall back to
    /// `displayName`, which is what every user verified before the app
    /// started recording the date will see.
    @Test func noDateMeansNoSentence() {
        let identity = VerifiedIdentity(rawName: "JORDAN JAMES FAVA", verifiedAt: nil)

        #expect(identity.statement == nil)
        #expect(identity.displayName == "Jordan James Fava")
    }

    /// The date is pinned to `en_US` rather than the device locale, because
    /// the website hardcodes the same format and one verification must not
    /// render two different dates on two surfaces.
    @Test func theDateIsFormattedTheWayTheWebsiteFormatsIt() {
        #expect(VerifiedIdentity.formatted(Self.verifiedAt).contains("2026"))
        // "September 4, 2026" — month spelled out, no leading zero.
        #expect(VerifiedIdentity.formatted(Self.verifiedAt).contains("September"))
    }

    // MARK: - Decoding

    /// `PhotoOwnerProfile` carries both halves, and the RPC gates them
    /// together — a name without its date is the fallback case, never a
    /// half-built sentence.
    @Test func ownerProfileComposesTheIdentityFromTheRPCFields() throws {
        let json = Data("""
        {
          "username": "Jordan",
          "is_verified": true,
          "display_name": "JORDAN JAMES FAVA",
          "identity_verified_at": null,
          "social_links": [{"platform":"instagram","handle":"jfava8021"}]
        }
        """.utf8)

        let owner = try JSONDecoder().decode(PhotoOwnerProfile.self, from: json)

        #expect(owner.verifiedIdentity?.displayName == "Jordan James Fava")
        #expect(owner.verifiedIdentity?.statement == nil)
        #expect(owner.socialLinks.items.first?.handle == "jfava8021")
    }

    @Test func ownerProfileWithoutANameHasNoIdentity() throws {
        let json = Data("""
        {
          "username": "Jordan",
          "is_verified": true,
          "display_name": null,
          "identity_verified_at": null,
          "social_links": []
        }
        """.utf8)

        let owner = try JSONDecoder().decode(PhotoOwnerProfile.self, from: json)
        #expect(owner.verifiedIdentity == nil)
    }
}
