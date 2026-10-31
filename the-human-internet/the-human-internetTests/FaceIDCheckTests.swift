//
//  FaceIDCheckTests.swift
//  the-human-internetTests
//

import Foundation
import LocalAuthentication
import Testing

@testable import the_human_internet

/// The website says signing in with Face ID shows a real person is logging
/// in. That only holds while the check accepts biometrics and nothing else,
/// and while every way of not passing leaves the user somewhere they can act.
struct FaceIDCheckTests {
    // MARK: Biometrics only

    @Test func policyIsBiometricsOnly() {
        #expect(FaceIDCheck.policy == .deviceOwnerAuthenticationWithBiometrics)
    }

    @Test func promptOffersNoPasscodeFallback() {
        #expect(FaceIDCheck.makeContext().localizedFallbackTitle == "")
    }

    // MARK: Outcomes

    private func outcome(_ code: LAError.Code, _ type: LABiometryType = .faceID) -> FaceIDOutcome {
        FaceIDOutcome(error: NSError(domain: LAErrorDomain, code: code.rawValue), biometryType: type)
    }

    @Test func cancellingIsNotAFailure() {
        #expect(outcome(.userCancel) == .cancelled)
        // Hidden by the empty fallback title, but if it's ever reached it
        // must not count as anything but a "no".
        #expect(outcome(.userFallback) == .cancelled)
    }

    @Test func theSystemClosingThePromptChecksAgainOnReturn() {
        for code: LAError.Code in [.systemCancel, .appCancel, .notInteractive] {
            #expect(outcome(code) == .interrupted)
        }
        #expect(FaceIDOutcome.interrupted.checksAgainOnReturn)
        #expect(!FaceIDOutcome.cancelled.checksAgainOnReturn)
    }

    @Test func setupProblemsAreToldApart() {
        #expect(outcome(.biometryNotEnrolled) == .notEnrolled)
        #expect(outcome(.passcodeNotSet) == .notEnrolled)
        #expect(outcome(.biometryLockout) == .lockedOut)
        #expect(outcome(.biometryNotAvailable, .faceID) == .notAllowed)
        #expect(outcome(.biometryNotAvailable, .none) == .unavailable)
    }

    @Test func anythingUnrecognisedIsAFailureNotAPass() {
        #expect(outcome(.authenticationFailed) == .failed)
        #expect(outcome(.invalidContext) == .failed)
        #expect(FaceIDOutcome(error: nil, biometryType: .faceID) == .failed)
        #expect(FaceIDOutcome(error: NSError(domain: "other", code: LAError.Code.userCancel.rawValue), biometryType: .faceID) == .failed)
    }

    // MARK: The gate's copy

    private static let notPassed: [FaceIDOutcome?] = [
        nil, .cancelled, .interrupted, .failed, .lockedOut, .notEnrolled, .notAllowed, .unavailable,
    ]

    @Test func askingAndCancellingInviteTheUserToStaySignedIn() {
        for outcome: FaceIDOutcome? in [nil, .cancelled, .interrupted] {
            let copy = FaceIDGateCopy(outcome: outcome, biometryType: .faceID, device: "iPhone")
            #expect(copy.title == "Are you still there?")
            #expect(copy.message == "Stay signed in by helping us check it's still you with Face ID.")
            #expect(copy.action == .check(title: "Use Face ID"))
        }
    }

    @Test func everyProblemExplainsWhyFaceIDIsNeeded() {
        for outcome: FaceIDOutcome in [.failed, .notEnrolled, .notAllowed, .unavailable] {
            let copy = FaceIDGateCopy(outcome: outcome, biometryType: .faceID, device: "iPhone")
            #expect(copy.message.contains("shows a real person is logging in"), "\(outcome)")
        }
    }

    @Test func onlyADeviceWithoutBiometricsHasNothingToTry() {
        for outcome in Self.notPassed {
            let copy = FaceIDGateCopy(outcome: outcome, biometryType: .faceID, device: "iPhone")
            #expect((copy.action == nil) == (outcome == .unavailable), "\(String(describing: outcome))")
        }
        #expect(FaceIDGateCopy(outcome: .notAllowed, biometryType: .faceID, device: "iPhone").action == .openSettings)
    }

    @Test func touchIDDevicesAreToldTouchID() {
        let copy = FaceIDGateCopy(outcome: .failed, biometryType: .touchID, device: "iPhone")
        #expect(copy.title == "Touch ID didn't recognize you.")
        #expect(!copy.message.contains("Face ID"))
    }
}
