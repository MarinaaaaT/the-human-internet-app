//
//  RemotePhotoSigner.swift
//  the-human-internet
//

import Foundation
import Supabase

enum RemotePhotoSignerError: Error {
    case emptyResponse
    /// `sign-photo` answered a capture-pipeline request without confirming
    /// it ran that pipeline — i.e. a backend that predates it, which signs
    /// the body as-is. What came back is then the *raw* capture, signed, with
    /// no watermark, and must never be uploaded as the shared photo.
    case capturePipelineNotConfirmed
}

/// The only C2PA signer, with the signing key never touching this device:
/// the Edge Function forwards to an AWS Lambda that signs via a KMS key it
/// can call but never see the material of. There's no on-device fallback.
///
/// Two entry points, one per `PhotoUploadQueue` path:
/// - `signCapture` — the capture pipeline (`server_side_watermark` on): the
///   raw capture goes up; the server signs it as a `digitalCapture`, burns
///   the brand mark into *that*, signs the result with the capture as its
///   C2PA parent ingredient, keeps the signed capture in `photo-originals`,
///   and returns the watermarked photo.
/// - `sign` — the older path: bytes already watermarked on device, signed
///   as-is as a `digitalCapture`.
///
/// Each request carries an App Attest assertion over the exact bytes sent,
/// when this device can produce one — see `AppAttestService`.
enum RemotePhotoSigner {
    /// Request header opting into the capture pipeline, echoed back by a
    /// backend that ran it. Mirrored in `sign-photo` as `PIPELINE_HEADER` /
    /// `CAPTURE_PIPELINE`.
    static let pipelineHeader = "X-Capture-Pipeline"
    static let capturePipeline = "server-watermark-v1"
    /// Names the photo so `sign-photo` can file its signed capture under the
    /// same `{user_id}/{photo_id}.jpg` path the photo itself uses.
    static let photoIDHeader = "X-Photo-Id"

    /// `sign-photo`'s answers meaning "the key you attested with is no good":
    /// unknown to the server, or its assertion didn't verify. Either way the
    /// fix is a fresh key, and one immediate retry gets it.
    private static let staleKeyCodes: Set<String> = ["attestation_key_unknown", "attestation_invalid"]

    /// Raw capture in, watermarked + signed photo out. Throws
    /// `capturePipelineNotConfirmed` rather than ever returning the raw
    /// capture back signed-but-unwatermarked.
    static func signCapture(rawData: Data, photoID: UUID) async throws -> Data {
        try await retryingOnStaleKey {
            let headers = await AppAttestService.shared.headers(attesting: rawData)
                .merging([
                    pipelineHeader: capturePipeline,
                    photoIDHeader: photoID.uuidString.lowercased(),
                ]) { attestation, _ in attestation }
            let (data, pipeline): (Data, String?) = try await supabase.functions.invoke(
                "sign-photo",
                options: FunctionInvokeOptions(headers: headers, body: rawData)
            ) { body, response in (body, response.value(forHTTPHeaderField: pipelineHeader)) }

            guard pipeline == capturePipeline else { throw RemotePhotoSignerError.capturePipelineNotConfirmed }
            guard !data.isEmpty else { throw RemotePhotoSignerError.emptyResponse }
            return data
        }
    }

    /// Already-watermarked JPEG in, signed JPEG out.
    static func sign(imageData: Data) async throws -> Data {
        try await retryingOnStaleKey {
            let headers = await AppAttestService.shared.headers(attesting: imageData)
            let signedData: Data = try await supabase.functions.invoke(
                "sign-photo",
                options: FunctionInvokeOptions(headers: headers, body: imageData)
            ) { data, _ in data }

            guard !signedData.isEmpty else { throw RemotePhotoSignerError.emptyResponse }
            return signedData
        }
    }

    private static func retryingOnStaleKey(_ attempt: () async throws -> Data) async throws -> Data {
        do {
            return try await attempt()
        } catch let error as FunctionsError {
            guard case .httpError(403, let data) = error,
                  let code = attestationErrorCode(data),
                  staleKeyCodes.contains(code)
            else { throw error }
            Log.attestation.error("sign-photo rejected App Attest key (\(code, privacy: .public)); re-registering")
            await AppAttestService.shared.discardKey()
            return try await attempt()
        }
    }

    private static func attestationErrorCode(_ body: Data) -> String? {
        struct Body: Decodable { let code: String? }
        return (try? JSONDecoder().decode(Body.self, from: body))?.code
    }
}
