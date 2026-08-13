//
//  FeatureFlagRepository.swift
//  the-human-internet
//

import Foundation
import Supabase

/// Remote, server-backed flags — not a local/per-device toggle. Flipping one
/// off (e.g. from the developer menu) changes behavior for every user, not
/// just the admin's own device; that's the point of `stripeIdentityVerification`,
/// which exists to unblock onboarding for everyone while Stripe Identity is
/// unavailable. Writes are enforced admin-only by RLS on `public.feature_flags`.
enum FeatureFlagKey {
    static let stripeIdentityVerification = "stripe_identity_verification"
    static let awsServerSideSigning = "aws_server_side_signing"
}

enum FeatureFlagRepository {
    private struct Row: Decodable {
        let key: String
        let enabled: Bool
    }

    static func fetchAll() async throws -> [String: Bool] {
        let rows: [Row] = try await supabase
            .from("feature_flags")
            .select()
            .execute()
            .value
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.enabled) })
    }

    static func setEnabled(key: String, enabled: Bool) async throws {
        try await supabase
            .from("feature_flags")
            .update(["enabled": enabled])
            .eq("key", value: key)
            .execute()
    }
}
