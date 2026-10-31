//
//  FaceIDCheck.swift
//  the-human-internet
//

import LocalAuthentication

/// The Face ID check run on every cold launch into a stored session — see
/// `FaceIDGateView`, which is how `RootView` reaches it. Not after a fresh
/// Sign in with Apple, which the person has just done.
///
/// Sign in with Apple lets Apple pick how it's approved — Face ID, Touch ID
/// or the device passcode. This asks for biometrics and nothing else.
enum FaceIDCheck {
    /// Biometrics only. `.deviceOwnerAuthentication` would fall back to the
    /// passcode, which is exactly what this check exists to rule out.
    /// `FaceIDCheckTests` pins it.
    static let policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics

    /// Shown in the Touch ID prompt. Face ID shows `NSFaceIDUsageDescription`
    /// instead, once, when it first asks permission.
    static let reason = "Show a real person is signing in."

    /// A fresh context for each check: one that has already succeeded would
    /// let a later evaluation through without asking again.
    static func makeContext() -> LAContext {
        let context = LAContext()
        // An empty title hides the "Enter Passcode" button the biometric
        // prompt otherwise offers after a failed match.
        context.localizedFallbackTitle = ""
        return context
    }

    /// What this device would use — Face ID, Touch ID, or `.none` — so the
    /// gate can say the right name before the first check has run.
    @MainActor
    static func biometryType() -> LABiometryType {
        let context = makeContext()
        _ = context.canEvaluatePolicy(policy, error: nil)
        return context.biometryType
    }

    @MainActor
    static func run() async -> FaceIDOutcome {
        let context = makeContext()
        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            return FaceIDOutcome(error: error, biometryType: context.biometryType)
        }
        do {
            try await context.evaluatePolicy(policy, localizedReason: reason)
            return .passed
        } catch {
            return FaceIDOutcome(error: error as NSError, biometryType: context.biometryType)
        }
    }
}

/// How a `FaceIDCheck` ended. Everything but `.passed` keeps the gate up,
/// each with its own explanation.
enum FaceIDOutcome: Equatable {
    case passed
    /// The user closed the prompt.
    case cancelled
    /// The system closed it — the app went to the background, say. Runs
    /// again by itself when the app comes back.
    case interrupted
    /// The face (or finger) didn't match.
    case failed
    /// Too many failed matches. Only the device passcode turns biometrics
    /// back on, and this check never accepts it, so the user has to lock
    /// and unlock the device first.
    case lockedOut
    /// The device has Face ID or Touch ID but it isn't set up, or there's
    /// no device passcode, which biometrics need.
    case notEnrolled
    /// The user said no to this app using Face ID. Settings has the switch.
    case notAllowed
    /// No biometric hardware at all.
    case unavailable

    init(error: NSError?, biometryType: LABiometryType) {
        guard let error, error.domain == LAErrorDomain,
              let code = LAError.Code(rawValue: error.code) else {
            self = .failed
            return
        }
        switch code {
        case .userCancel, .userFallback:
            self = .cancelled
        case .systemCancel, .appCancel, .notInteractive:
            self = .interrupted
        case .biometryLockout:
            self = .lockedOut
        case .biometryNotEnrolled, .passcodeNotSet:
            self = .notEnrolled
        // Also what a refused permission looks like, and only the biometry
        // type tells the two apart: it's still reported when the app has
        // been refused, and `.none` when there's no hardware.
        case .biometryNotAvailable:
            self = biometryType == .none ? .unavailable : .notAllowed
        default:
            self = .failed
        }
    }
}
