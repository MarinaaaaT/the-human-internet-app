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
/// The resolution is easy to get subtly wrong in the direction that matters —
/// `stripe_identity_verification` failing *open* would wave a cohort past an
/// onboarding step, and nothing would visibly break while it happened.
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
    /// finishes, and the state it stays in if the fetch fails.
    @Test func unloadedFlagsFallBackInOppositeDirectionsPerFlag() {
        let appState = AppState()
        appState.isAdmin = true
        #expect(appState.featureFlags.isEmpty)

        // Verification stays required of everyone...
        #expect(appState.isStripeIdentityVerificationEnabled)
        // ...while remote signing stays opt-in.
        #expect(!appState.isAWSServerSideSigningEnabled)
    }

    /// A shared default would have to be wrong for one of these two.
    @Test func fallbacksArePerFlag() {
        #expect(FeatureFlagKey.fallbackAudience(for: FeatureFlagKey.stripeIdentityVerification) == .all)
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
    /// the flag reads as unset — never as `off` for a flag whose safe
    /// direction is on.
    @Test func anUnrecognisedAudienceLeavesTheFlagUnsetRatherThanOff() {
        #expect(FeatureFlagAudience(rawValue: "beta_testers") == nil)

        let appState = AppState()
        appState.featureFlags = [:]  // what fetchAll produces when it can't map the value

        #expect(appState.isStripeIdentityVerificationEnabled)
    }
}
