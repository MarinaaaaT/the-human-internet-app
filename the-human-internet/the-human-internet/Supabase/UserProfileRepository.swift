//
//  UserProfileRepository.swift
//  the-human-internet
//

import Foundation
import Supabase

enum UserProfileRepository {
    static func fetch(userID: UUID) async throws -> HumanUser? {
        let rows: [HumanUser] = try await supabase
            .from("users")
            .select()
            .eq("id", value: userID)
            .execute()
            .value
        return rows.first
    }

    static func upsert(_ user: HumanUser) async throws {
        try await supabase
            .from("users")
            .upsert(user)
            .execute()
    }

    /// Fetches the profile for `userID`, creating a fresh row at the `.profile`
    /// onboarding step if this identity has never signed in before.
    static func resolveOrCreate(userID: UUID) async throws -> HumanUser {
        if let existing = try await fetch(userID: userID) {
            return existing
        }
        let fresh = HumanUser(id: userID, onboardingStep: .profile)
        try await upsert(fresh)
        return fresh
    }

    /// `users_username_unique_idx` (case-insensitive, partial on non-empty username)
    /// raises Postgres error 23505 on conflict.
    static func isUsernameConflict(_ error: Error) -> Bool {
        (error as? PostgrestError)?.code == "23505"
    }

    /// Creates (or, on retry, resumes) a Stripe Identity VerificationSession
    /// via the `stripe-identity-session` Edge Function and returns its hosted
    /// verification URL. The Stripe secret key never leaves the server side.
    static func createIdentityVerificationSession() async throws -> URL {
        struct Response: Decodable { let url: URL }
        let response: Response = try await supabase.functions.invoke("stripe-identity-session")
        return response.url
    }

    /// Deliberately not a field on `HumanUser`: that struct round-trips
    /// through `upsert`, and `is_admin` must never be settable by writing
    /// the client's own copy of its row back — see the
    /// `prevent_self_admin_escalation` triggers on `public.users`. This is a
    /// separate, narrow, read-only query instead.
    static func fetchIsAdmin(userID: UUID) async throws -> Bool {
        struct Row: Decodable {
            let isAdmin: Bool
            enum CodingKeys: String, CodingKey { case isAdmin = "is_admin" }
        }
        let rows: [Row] = try await supabase
            .from("users")
            .select("is_admin")
            .eq("id", value: userID)
            .execute()
            .value
        return rows.first?.isAdmin ?? false
    }
}
