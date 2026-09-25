//
//  AppAttestService.swift
//  the-human-internet
//

import CryptoKit
import DeviceCheck
import Foundation
import Supabase

/// Proves to `sign-photo` that a signing request came from this app, unmodified,
/// on real Apple hardware — via Apple's App Attest. Without it, a session
/// token alone was enough to get any bytes signed as a camera capture,
/// including an AI image sent with curl.
///
/// Once per install it registers a Secure Enclave key: fetch a challenge from
/// `app-attest-challenge`, have Apple attest the key over it, hand the
/// attestation to `app-attest-register`. After that, every photo gets an
/// assertion from that key over the **exact bytes being signed**, sent as two
/// headers the Edge Function verifies before signing anything.
///
/// **This never blocks an upload on its own.** Anything that goes wrong here —
/// no App Attest on this device (the Simulator), Apple's service unreachable,
/// the backend functions not deployed yet — leaves the request unattested,
/// and `sign-photo` decides: it signs and logs while the `require_app_attest`
/// flag is off for this user, and refuses once it's on. So the enforcement
/// switch lives entirely server-side, like every other one this app has.
///
/// What it proves is the request's origin, not the pixels': a jailbroken
/// device can still hook the capture path. See the backend's
/// `_shared/appAttest.ts` for the verification half.
actor AppAttestService {
    static let shared = AppAttestService()

    /// Header names — mirrored in `sign-photo`.
    static let keyIDHeader = "X-App-Attest-Key-Id"
    static let assertionHeader = "X-App-Attest-Assertion"

    /// The registered key id. Per install, not per user: the key attests the
    /// app and device, and survives sign-out on purpose. App Attest keys don't
    /// survive a reinstall, and neither does `UserDefaults`; a key restored
    /// from a backup onto another device fails with `invalidKey` and is
    /// replaced.
    private static let keyIDDefaultsKey = "appAttest.registeredKeyID"

    /// After a failed registration, how long to wait before trying again. The
    /// upload queue retries on its own schedule, and without this each retry
    /// of each pending photo would make a fresh key and a network round-trip
    /// while, say, the backend functions aren't deployed.
    private static let registrationRetryInterval: TimeInterval = 10 * 60

    private var registration: Task<String, Error>?
    private var lastRegistrationFailure: Date?

    /// Headers attesting to `body`, or none if this request has to go
    /// unattested. Never throws — see the type's doc comment.
    func headers(attesting body: Data) async -> [String: String] {
        let service = DCAppAttestService.shared
        guard service.isSupported else { return [:] }

        let keyID: String
        do {
            keyID = try await registeredKeyID()
        } catch {
            Log.attestation.error("App Attest registration failed: \(error, privacy: .public)")
            return [:]
        }

        do {
            let clientDataHash = Data(SHA256.hash(data: body))
            let assertion = try await service.generateAssertion(keyID, clientDataHash: clientDataHash)
            return [
                Self.keyIDHeader: keyID,
                Self.assertionHeader: assertion.base64EncodedString(),
            ]
        } catch {
            Log.attestation.error("App Attest assertion failed: \(error, privacy: .public)")
            if (error as? DCError)?.code == .invalidKey { discardKey() }
            return [:]
        }
    }

    /// Forgets the registered key, so the next request registers a new one.
    /// Called when the device says the key is gone, or when `sign-photo`
    /// says it doesn't know or can't verify it.
    func discardKey() {
        UserDefaults.standard.removeObject(forKey: Self.keyIDDefaultsKey)
        lastRegistrationFailure = nil
    }

    private func registeredKeyID() async throws -> String {
        if let keyID = UserDefaults.standard.string(forKey: Self.keyIDDefaultsKey) {
            return keyID
        }
        // Two photos sign concurrently; they must share one registration.
        if let registration {
            return try await registration.value
        }
        if let lastRegistrationFailure,
           Date().timeIntervalSince(lastRegistrationFailure) < Self.registrationRetryInterval {
            throw AppAttestServiceError.registrationBackingOff
        }

        let task = Task { try await Self.register() }
        registration = task
        defer { registration = nil }
        do {
            let keyID = try await task.value
            UserDefaults.standard.set(keyID, forKey: Self.keyIDDefaultsKey)
            Log.attestation.info("Registered App Attest key")
            return keyID
        } catch {
            lastRegistrationFailure = Date()
            throw error
        }
    }

    private static func register() async throws -> String {
        let service = DCAppAttestService.shared
        let keyID = try await service.generateKey()

        struct ChallengeResponse: Decodable { let challenge: String }
        let response: ChallengeResponse = try await supabase.functions.invoke("app-attest-challenge")
        guard let challenge = Data(base64Encoded: response.challenge) else {
            throw AppAttestServiceError.malformedChallenge
        }

        let attestation = try await service.attestKey(
            keyID,
            clientDataHash: Data(SHA256.hash(data: challenge))
        )

        struct RegisterBody: Encodable {
            let keyId: String
            let attestation: String
            let challenge: String
        }
        try await supabase.functions.invoke(
            "app-attest-register",
            options: FunctionInvokeOptions(
                body: RegisterBody(
                    keyId: keyID,
                    attestation: attestation.base64EncodedString(),
                    challenge: response.challenge
                )
            )
        )
        return keyID
    }
}

enum AppAttestServiceError: Error {
    case registrationBackingOff
    case malformedChallenge
}
