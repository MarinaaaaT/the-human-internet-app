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
}
