//
//  Models.swift
//  the-human-internet
//

import Foundation

/// Values mirror the `users_privacy_check` constraint on `public.users`.
enum PrivacyLevel: String, CaseIterable, Identifiable, Codable, Hashable {
    case public_ = "Public"
    case humansOnly = "Humans Only"

    var id: String { rawValue }

    /// Falls back to the *more* private of the two — see `DatabaseEnum`.
    init(from decoder: Decoder) throws {
        self = try DatabaseEnum.decode(from: decoder, fallback: .humansOnly)
    }
}

/// Values mirror the `users_verification_status_check` constraint on
/// `public.users`, which permits all four of these. `unverified` is that
/// column's default, so it's what any row the app didn't write itself
/// carries — and leaving it out of this enum is exactly what broke Sign in
/// with Apple (see `DatabaseEnum`).
enum VerificationStatus: String, Codable, Hashable {
    case unverified
    case inProgress = "in_progress"
    case verified
    case failed

    /// Falls back to `unverified`: a status this build can't read must never
    /// be mistaken for a verified human, which is the one claim the whole
    /// product rests on.
    init(from decoder: Decoder) throws {
        self = try DatabaseEnum.decode(from: decoder, fallback: .unverified)
    }
}

/// Mirrors an onboarding_step value in the `users` table, so progress can be
/// resumed after the app is killed mid-flow. Values mirror the
/// `users_onboarding_step_check` constraint on `public.users`.
enum OnboardingStep: String, Codable, Hashable {
    case profile
    case verify
    case welcomeHuman = "welcome_human"
    case completed

    /// Falls back to the *first* step rather than a later one: replaying
    /// onboarding is recoverable, whereas reading an unknown step as
    /// `completed` would wave someone into the app having skipped it.
    init(from decoder: Decoder) throws {
        self = try DatabaseEnum.decode(from: decoder, fallback: .profile)
    }
}

/// Shared decoding for the three enums above, each of which mirrors a
/// Postgres `text` column whose permitted values are pinned by a CHECK
/// constraint in the database rather than by anything in this app.
///
/// A synthesized `Decodable` conformance throws on any string it doesn't
/// recognise, and that has real teeth here: `users.verification_status`
/// defaults to `unverified` and its CHECK constraint allows it, but this
/// enum listed only the other three. `AppState.hydrate` decodes the user row
/// before anything else can happen, so that one unlisted value failed
/// sign-in outright — "The data couldn't be read because it isn't in the
/// correct format", with no way into the app to recover.
///
/// Sign-in is the worst possible place to be strict: a value added to a
/// CHECK constraint reaches every already-installed build the moment it's
/// written, long before any of them ship an update that knows about it. So
/// an unrecognised value logs and degrades to a declared fallback instead of
/// throwing. Each fallback is chosen to err toward claiming *less* about a
/// user than the server said, never more.
enum DatabaseEnum {
    static func decode<Value: RawRepresentable>(
        from decoder: Decoder,
        fallback: Value
    ) throws -> Value where Value.RawValue == String {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Value(rawValue: raw) else {
            Log.auth.error(
                "Unrecognised \(String(describing: Value.self), privacy: .public) value '\(raw, privacy: .public)' — falling back to '\(fallback.rawValue, privacy: .public)'"
            )
            return fallback
        }
        return value
    }
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
