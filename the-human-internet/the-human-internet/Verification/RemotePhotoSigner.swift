//
//  RemotePhotoSigner.swift
//  the-human-internet
//

import Foundation
import Supabase

enum RemotePhotoSignerError: Error {
    case emptyResponse
}

/// The only C2PA signer: JPEG in, C2PA-signed JPEG out, with the signing key
/// never touching this device. The Edge Function forwards the bytes to an AWS
/// Lambda that signs via a KMS key it can call but never see the material of.
///
/// There's no on-device fallback — the bundled dev key that used to back one
/// was removed. `PhotoUploadQueue.drive()` calls this for every photo unless
/// an admin has switched on the developer tools' "Skip C2PA verification".
///
/// Each request carries an App Attest assertion over the exact bytes being
/// signed, when this device can produce one — see `AppAttestService`.
enum RemotePhotoSigner {
    /// `sign-photo`'s answers meaning "the key you attested with is no good":
    /// unknown to the server, or its assertion didn't verify. Either way the
    /// fix is a fresh key, and one immediate retry gets it.
    private static let staleKeyCodes: Set<String> = ["attestation_key_unknown", "attestation_invalid"]

    static func sign(imageData: Data) async throws -> Data {
        do {
            return try await attemptSign(imageData: imageData)
        } catch let error as FunctionsError {
            guard case .httpError(403, let data) = error,
                  let code = attestationErrorCode(data),
                  staleKeyCodes.contains(code)
            else { throw error }
            Log.attestation.error("sign-photo rejected App Attest key (\(code, privacy: .public)); re-registering")
            await AppAttestService.shared.discardKey()
            return try await attemptSign(imageData: imageData)
        }
    }

    private static func attemptSign(imageData: Data) async throws -> Data {
        let headers = await AppAttestService.shared.headers(attesting: imageData)
        let options = FunctionInvokeOptions(headers: headers, body: imageData)
        let signedData: Data = try await supabase.functions.invoke(
            "sign-photo",
            options: options
        ) { data, _ in data }

        guard !signedData.isEmpty else { throw RemotePhotoSignerError.emptyResponse }
        return signedData
    }

    private static func attestationErrorCode(_ body: Data) -> String? {
        struct Body: Decodable { let code: String? }
        return (try? JSONDecoder().decode(Body.self, from: body))?.code
    }
}
