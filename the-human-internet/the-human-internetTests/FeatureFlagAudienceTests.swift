//
//  FeatureFlagAudienceTests.swift
//  the-human-internetTests
//

import Foundation
import Testing

@testable import the_human_internet

/// Covers the three-way feature-flag audience: who a flag is on for, and what
/// happens when the server doesn't tell this build anything usable about it.
///
/// The resolution is easy to get subtly wrong in the direction that matters,
/// and nothing visibly breaks while it's wrong — `stripe_identity_test_mode`
/// failing *open* would point real users at Stripe's sandbox, where a
/// verification proves nothing about a real person.
struct FeatureFlagAudienceTests {
    @Test func allIsOnForEveryone() {
        #expect(FeatureFlagAudience.all.includes(isAdmin: true))
        #expect(FeatureFlagAudience.all.includes(isAdmin: false))
    }

    @Test func adminIsOnOnlyForAdmins() {
        #expect(FeatureFlagAudience.admin.includes(isAdmin: true))
        #expect(!FeatureFlagAudience.admin.includes(isAdmin: false))
    }

    @Test func offIsOnForNobody() {
        #expect(!FeatureFlagAudience.off.includes(isAdmin: true))
        #expect(!FeatureFlagAudience.off.includes(isAdmin: false))
    }

    /// Pins the enum against `feature_flags_audience_check`. Same drift risk
    /// as the enums in `HumanUserDecodingTests` — the permitted values live
    /// in Postgres, not here.
    @Test func rawValuesMatchTheDatabaseCheckConstraint() {
        #expect(Set(FeatureFlagAudience.allCases.map(\.rawValue)) == ["all", "admin", "off"])
    }

    // MARK: - Resolution through AppState

    @Test func adminOnlyFlagIsOffForANonAdmin() {
        let appState = AppState()
        appState.featureFlags = [FeatureFlagKey.awsServerSideSigning: .admin]

        appState.isAdmin = false
        #expect(!appState.isAWSServerSideSigningEnabled)

        appState.isAdmin = true
        #expect(appState.isAWSServerSideSigningEnabled)
    }

    /// The picker edits the server's value; it must not start showing "Off"
    /// to a non-admin just because the flag isn't on for them.
    @Test func theAudienceShownIsTheStoredOneNotTheResolvedOne() {
        let appState = AppState()
        appState.featureFlags = [FeatureFlagKey.awsServerSideSigning: .admin]
        appState.isAdmin = false

        #expect(appState.audience(for: FeatureFlagKey.awsServerSideSigning) == .admin)
        #expect(!appState.isAWSServerSideSigningEnabled)
    }

    // MARK: - Fallbacks

    /// Flags that never loaded — the state `AppState` is in before `hydrate`
    /// finishes, and the state it stays in if the fetch fails. Every flag
    /// currently fails closed; an admin account is used here because it's the
    /// *least* restricted case, so anything switched on for a non-admin too
    /// would show up.
    @Test func unloadedFlagsAreAllOff() {
        let appState = AppState()
        appState.isAdmin = true
        #expect(appState.featureFlags.isEmpty)

        #expect(!appState.isStripeIdentityVerificationEnabled)
        #expect(!appState.isStripeIdentityTestModeEnabled)
        #expect(!appState.isAWSServerSideSigningEnabled)
    }

    /// Declared per flag rather than shared, even though all three agree
    /// today: the safe direction belongs to what a flag guards.
    /// `stripeIdentityVerification` fell back to `.all` while the verify step
    /// was mandatory, and moved once it wasn't.
    @Test func fallbacksAreDeclaredPerFlag() {
        #expect(FeatureFlagKey.fallbackAudience(for: FeatureFlagKey.stripeIdentityVerification) == .off)
        #expect(FeatureFlagKey.fallbackAudience(for: FeatureFlagKey.stripeIdentityTestMode) == .off)
        #expect(FeatureFlagKey.fallbackAudience(for: FeatureFlagKey.awsServerSideSigning) == .off)
    }

    /// A flag guarding something this build doesn't implement yet.
    @Test func anUnknownFlagKeyIsOff() {
        let appState = AppState()
        appState.isAdmin = true
        #expect(appState.audience(for: "some_future_flag") == .off)
    }

    /// An audience string added server-side that this build doesn't know
    /// drops out of the dictionary in `FeatureFlagRepository.fetchAll`, so
    /// the flag reads as unset and its own fallback applies — never as
    /// whatever the unreadable string might have meant.
    @Test func anUnrecognisedAudienceFallsBackRatherThanBeingGuessedAt() {
        #expect(FeatureFlagAudience(rawValue: "beta_testers") == nil)

        let appState = AppState()
        appState.isAdmin = true
        appState.featureFlags = [:]  // what fetchAll produces when it can't map the value

        #expect(appState.audience(for: FeatureFlagKey.stripeIdentityTestMode) == .off)
        #expect(!appState.isStripeIdentityTestModeEnabled)
    }

    // MARK: - The test-environment flag

    /// The flag that must never resolve on for a real user. `.all` is refused
    /// by the developer menu, but the resolution can't lean on that: a value
    /// written straight into the table, or by a build without the guard,
    /// reaches this code path all the same.
    @Test func testModeStaysOffForANonAdminEvenWhenSetToAll() {
        let appState = AppState()
        appState.featureFlags = [FeatureFlagKey.stripeIdentityTestMode: .all]

        appState.isAdmin = false
        #expect(!appState.isStripeIdentityTestModeEnabled)

        appState.isAdmin = true
        #expect(appState.isStripeIdentityTestModeEnabled)
    }

    @Test func testModeIsOnForAnAdminWhenSetToAdmin() {
        let appState = AppState()
        appState.featureFlags = [FeatureFlagKey.stripeIdentityTestMode: .admin]

        appState.isAdmin = true
        #expect(appState.isStripeIdentityTestModeEnabled)

        appState.isAdmin = false
        #expect(!appState.isStripeIdentityTestModeEnabled)
    }

    /// The developer menu's half of the same rule.
    @Test func thePickerRefusesToSetTheTestFlagToEveryone() {
        #expect(
            FeatureFlagPolicy.rejectionReason(
                setting: FeatureFlagKey.stripeIdentityTestMode,
                to: .all
            ) == "Non-admins should not be allowed to verify identity with Stripe sandbox."
        )
    }

    @Test func theTestFlagsOtherAudiencesArePermitted() {
        #expect(FeatureFlagPolicy.rejectionReason(setting: FeatureFlagKey.stripeIdentityTestMode, to: .admin) == nil)
        #expect(FeatureFlagPolicy.rejectionReason(setting: FeatureFlagKey.stripeIdentityTestMode, to: .off) == nil)
    }

    /// The restriction is specific to the sandbox flag — it must not leak
    /// onto flags that are meant to reach everyone.
    @Test func otherFlagsCanStillBeSetToEveryone() {
        #expect(FeatureFlagPolicy.rejectionReason(setting: FeatureFlagKey.stripeIdentityVerification, to: .all) == nil)
        #expect(FeatureFlagPolicy.rejectionReason(setting: FeatureFlagKey.awsServerSideSigning, to: .all) == nil)
    }
}
