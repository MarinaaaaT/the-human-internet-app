//
//  Models.swift
//  the-human-internet
//

import Foundation

enum PrivacyLevel: String, CaseIterable, Identifiable, Codable, Hashable {
    case public_ = "Public"
    case humansOnly = "Humans Only"

    var id: String { rawValue }
}

enum VerificationStatus: String, Codable, Hashable {
    case inProgress = "in_progress"
    case verified
    case failed
}

/// Mirrors an onboarding_step value in the `users` table, so progress can be
/// resumed after the app is killed mid-flow.
enum OnboardingStep: String, Codable, Hashable {
    case profile
    case verify
    case welcomeHuman = "welcome_human"
    case completed
}

/// Maps 1:1 to a row in the `users` table. Deliberately has no field for the
/// SSN last-four collected during identity verification — that value must
/// never leave `IdentityVerificationView`'s local state.
struct HumanUser: Codable, Hashable {
    var id: UUID?
    var username: String = ""
    var profileIconIndex: Int = 0
    var phoneNumber: String = ""
    var privacy: PrivacyLevel = .public_
    var verificationStatus: VerificationStatus = .inProgress
    var onboardingStep: OnboardingStep = .profile

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case profileIconIndex = "profile_icon_index"
        case phoneNumber = "phone_number"
        case privacy
        case verificationStatus = "verification_status"
        case onboardingStep = "onboarding_step"
    }
}

/// Maps 1:1 to a row in the `photos` table. No privacy field here — per the
/// product spec, signed-in app users see full contents for both Public and
/// Humans Only photos, so visibility only matters on the (separate,
/// signed-out) web verification page, which would join to the owner's
/// `users.privacy` rather than duplicating it per-photo.
struct VerifiedPhoto: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: UUID
    var storagePath: String
    var capturedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case storagePath = "storage_path"
        case capturedAt = "captured_at"
    }

    var verificationLink: String {
        "the-human-internet.com/\(id.uuidString.prefix(8).lowercased())"
    }

    var deepLinkURL: URL {
        URL(string: "thehumaninternet://photo/\(id.uuidString)")!
    }
}
