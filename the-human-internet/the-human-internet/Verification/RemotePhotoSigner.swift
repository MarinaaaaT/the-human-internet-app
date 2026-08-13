//
//  RemotePhotoSigner.swift
//  the-human-internet
//

import Foundation
import Supabase

enum RemotePhotoSignerError: Error {
    case emptyResponse
}

/// Server-side counterpart to `PhotoSigner.sign(imageData:)`: same input/output
/// shape (raw JPEG in, C2PA-signed JPEG out), but the signing key never
/// touches this device. The Edge Function forwards the bytes to an AWS Lambda
/// that signs via a KMS key it can call but never see the material of.
///
/// Gated behind `AppState.isAWSServerSideSigningEnabled` — see
/// `CameraCaptureView.capture()` for the switch between this and the
/// on-device `PhotoSigner`.
enum RemotePhotoSigner {
    static func sign(imageData: Data) async throws -> Data {
        let options = FunctionInvokeOptions(body: imageData)
        let signedData: Data = try await supabase.functions.invoke(
            "sign-photo",
            options: options
        ) { data, _ in data }

        guard !signedData.isEmpty else { throw RemotePhotoSignerError.emptyResponse }
        return signedData
    }
}
