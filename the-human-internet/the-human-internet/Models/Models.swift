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

/// Maps 1:1 to a row in the `users` table. Deliberately has no SSN field:
/// identity verification runs through Stripe Identity (document + selfie
/// checks only), which never collects or sends an SSN.
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
/// Where a photo is in the capture → sign → upload pipeline, as far as the
/// UI is concerned. Derived from `AppState`'s two ID sets by
/// `AppState.uploadState(for:)` rather than stored — the sets stay the
/// source of truth, this is the one shape views need. An enum because the
/// three states are mutually exclusive, which two booleans wouldn't express.
enum PhotoUploadState {
    case idle, processing, failed
}

struct VerifiedPhoto: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: UUID
    var storagePath: String
    var capturedAt: Date
    /// `thehumaninternet://photo/{id}`, generated once at upload time and
    /// persisted rather than recomputed — see PhotoRepository.upload.
    var verificationDeepLink: String
    /// 8-character random code used for the short public link — see
    /// `generateShortCode()`. Generated once, client-side, alongside `id`
    /// (PhotoUploadQueue.enqueue) so it stays stable across retry attempts.
    var shortCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case storagePath = "storage_path"
        case capturedAt = "captured_at"
        case verificationDeepLink = "verification_deep_link"
        case shortCode = "short_code"
    }

    /// Host of the public web verification page. Must stay in step with the
    /// website's `/[photoId]` route.
    private static let webHost = "the-human-internet.com"

    /// Custom URL scheme registered in `Info.plist`. Swaps to a Universal
    /// Link once the website hosts an apple-app-site-association file.
    static let deepLinkScheme = "thehumaninternet"
    /// The `photo` in `thehumaninternet://photo/{id}` — a URL host, not a
    /// path component, which is what `RootView.handle(url:)` matches on.
    static let deepLinkHost = "photo"

    /// Storage object path for a photo: `{user_id}/{photo_id}.jpg`.
    ///
    /// Both components are lowercased to match Postgres's canonical uuid text
    /// rendering — Swift's `UUID.uuidString` is uppercase. The Storage RLS
    /// policy casts to `uuid` and so compares by value regardless, but an
    /// earlier case-sensitive version of that policy silently rejected every
    /// upload, so the client stays consistent defensively.
    static func storagePath(userID: UUID, photoID: UUID) -> String {
        "\(userID.uuidString.lowercased())/\(photoID.uuidString.lowercased()).jpg"
    }

    /// In-app deep link for a photo. Lowercased for the same reason as
    /// `storagePath`.
    static func deepLink(photoID: UUID) -> String {
        "\(deepLinkScheme)://\(deepLinkHost)/\(photoID.uuidString.lowercased())"
    }

    /// Base58 (Bitcoin alphabet, no 0/O/I/l — avoids visual ambiguity when
    /// read aloud or handwritten) so an 8-character code still has ~1.3×10^14
    /// possible values. The DB also has a matching CHECK constraint and a
    /// unique index; collision odds at that space are negligible so there's
    /// no client-side retry — see `photos_short_code_format` in the migration.
    static func generateShortCode() -> String {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }

    /// Display form, without a scheme — shown in the share sheet. Short
    /// rather than the full id: it doubles as the lookup key the web
    /// verification page queries by (falling back to the bare `id` for links
    /// shared before this existed), so it must stay collision-free.
    var verificationLink: String {
        "\(Self.webHost)/\(shortCode)"
    }

    /// The link to actually share. Carries the scheme so it's tappable
    /// wherever it's pasted, unlike the bare `verificationLink` display form.
    ///
    /// Can't fail to construct: the host is a literal and the path is a UUID.
    var verificationURL: URL {
        URL(string: "https://\(verificationLink)")!
    }
}

extension VerifiedPhoto {
    /// The initializer every real (non-preview, non-test) photo goes through.
    ///
    /// `storagePath` and `verificationDeepLink` are derived rather than passed
    /// in, so the two formats can't drift between the three places a photo
    /// gets constructed — `PhotoRepository.upload` and `PhotoUploadQueue`'s
    /// enqueue and resume paths. Both are part of a contract that outlives the
    /// app: the storage path is matched by a Storage RLS policy, and links
    /// already shared in the wild can't be re-minted.
    ///
    /// Defined in an extension so the memberwise initializer survives — the
    /// previews and tests that need to construct an arbitrary path still use it.
    init(id: UUID, userID: UUID, capturedAt: Date, shortCode: String) {
        self.init(
            id: id,
            userID: userID,
            storagePath: Self.storagePath(userID: userID, photoID: id),
            capturedAt: capturedAt,
            verificationDeepLink: Self.deepLink(photoID: id),
            shortCode: shortCode
        )
    }
}
