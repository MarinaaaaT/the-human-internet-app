//
//  HumanUserDecodingTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// Pins the contract between `HumanUser` and the `public.users` table.
///
/// Every one of these enums mirrors a Postgres `text` column whose permitted
/// values live in a CHECK constraint on the server, so the two halves can
/// drift without anything failing to compile. When they did — the constraint
/// allowed (and defaulted to) `verification_status = 'unverified'`, which
/// `VerificationStatus` didn't list — the damage was total rather than
/// cosmetic: `AppState.hydrate` decodes the user row immediately after Sign
/// in with Apple, so the throw surfaced as "The data couldn't be read
/// because it isn't in the correct format" and left no way into the app.
///
/// If a case here needs changing, change the CHECK constraint in the same
/// breath — `users_verification_status_check`, `users_privacy_check`,
/// `users_onboarding_step_check`.
struct HumanUserDecodingTests {
    /// Shaped like a real PostgREST row, extra server-side columns included:
    /// `is_admin`, `created_at`, `stripe_identity_session_id` and
    /// `phone_number` are all deliberately absent from `HumanUser` and must
    /// stay ignorable. `phone_number` is the newest of them — the column still
    /// exists and older rows still carry values, the app just stopped
    /// collecting or reading it.
    private func userRowJSON(verificationStatus: String) -> Data {
        Data("""
        {
          "id": "2e9232a7-0f69-4bec-af8c-0455d3af107d",
          "username": "Marina",
          "profile_icon_index": 2,
          "phone_number": "2035813137",
          "privacy": "Public",
          "verification_status": "\(verificationStatus)",
          "onboarding_step": "completed",
          "stripe_identity_session_id": null,
          "is_admin": true,
          "created_at": "2026-08-04T21:01:31.731583+00:00"
        }
        """.utf8)
    }

    /// The four values `users_verification_status_check` permits. All four
    /// reach the client, so all four have to decode.
    @Test(arguments: ["unverified", "in_progress", "verified", "failed"])
    func decodesEveryVerificationStatusTheDatabaseAllows(rawValue: String) throws {
        let user = try JSONDecoder().decode(HumanUser.self, from: userRowJSON(verificationStatus: rawValue))

        #expect(user.verificationStatus.rawValue == rawValue)
        #expect(user.username == "Marina")
        #expect(user.onboardingStep == .completed)
    }

    /// `unverified` is the column default, so it's what every row the app
    /// didn't write itself carries — the case that actually broke sign-in.
    @Test func decodesTheColumnDefault() throws {
        let user = try JSONDecoder().decode(HumanUser.self, from: userRowJSON(verificationStatus: "unverified"))
        #expect(user.verificationStatus == .unverified)
    }

    /// A value added to the CHECK constraint tomorrow lands on every build
    /// already installed today. Degrading beats throwing, because throwing
    /// here means nobody can sign in at all.
    @Test func unknownStatusDegradesInsteadOfFailingTheWholeSignIn() throws {
        let user = try JSONDecoder().decode(HumanUser.self, from: userRowJSON(verificationStatus: "pending_review"))

        // Cautious direction: an unreadable status must never be mistaken
        // for a verified human.
        #expect(user.verificationStatus == .unverified)
        // The rest of the row still has to survive intact.
        #expect(user.username == "Marina")
        #expect(user.onboardingStep == .completed)
    }

    @Test func unknownOnboardingStepRestartsRatherThanSkipsOnboarding() throws {
        let json = Data("""
        {
          "id": "2e9232a7-0f69-4bec-af8c-0455d3af107d",
          "username": "Marina",
          "profile_icon_index": 0,
          "phone_number": "",
          "privacy": "Public",
          "verification_status": "verified",
          "onboarding_step": "confirm_phone"
        }
        """.utf8)

        let user = try JSONDecoder().decode(HumanUser.self, from: json)
        #expect(user.onboardingStep == .profile)
    }

    @Test func unknownPrivacyFallsBackToTheMorePrivateOption() throws {
        let json = Data("""
        {
          "id": "2e9232a7-0f69-4bec-af8c-0455d3af107d",
          "username": "Marina",
          "profile_icon_index": 0,
          "phone_number": "",
          "privacy": "Followers Only",
          "verification_status": "verified",
          "onboarding_step": "completed"
        }
        """.utf8)

        let user = try JSONDecoder().decode(HumanUser.self, from: json)
        #expect(user.privacy == .humansOnly)
    }

    /// Encoding stays strict and lossless — the raw values written back are
    /// what the CHECK constraints accept, or the upsert is rejected outright.
    @Test func encodesRawValuesTheDatabaseAccepts() throws {
        var user = HumanUser(id: UUID())
        user.verificationStatus = .unverified
        user.onboardingStep = .welcomeHuman
        user.privacy = .humansOnly

        let encoded = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(user)) as? [String: Any]

        #expect(encoded?["verification_status"] as? String == "unverified")
        #expect(encoded?["onboarding_step"] as? String == "welcome_human")
        #expect(encoded?["privacy"] as? String == "Humans Only")
    }
}
