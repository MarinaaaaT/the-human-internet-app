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
