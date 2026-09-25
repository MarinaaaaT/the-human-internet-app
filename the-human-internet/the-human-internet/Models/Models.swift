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
///
/// Identity verification is optional, so `unverified` — never started, or
/// deliberately skipped — is a legitimate resting state rather than a stage on
/// the way to `verified`. `inProgress` means "submitted to Stripe, awaiting the
/// result", which only the stripe-identity-webhook Edge Function resolves.
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

/// A social account a verified user chose to show on their public
/// verification page.
///
/// Values mirror the platform whitelist inside `is_valid_social_links()` on
/// `public.users.social_links`, and `SOCIAL_PLATFORMS` in the website's
/// `src/lib/photos/socialLinks.ts`. All three have to move together: the
/// database rejects a platform it doesn't list (taking the whole upsert with
/// it), and the website builds every href from its own copy of the table.
enum SocialPlatform: String, CaseIterable, Identifiable, Codable, Hashable {
    case instagram
    case x
    case tiktok
    case youtube
    case linkedin
    case github
    case reddit
    case facebook

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .x: return "X"
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .linkedin: return "LinkedIn"
        case .github: return "GitHub"
        case .reddit: return "Reddit"
        case .facebook: return "Facebook"
        }
    }

    /// What the handle is called on that platform, for the field's prompt.
    var handlePlaceholder: String {
        switch self {
        case .linkedin: return "your-profile-slug"
        case .facebook: return "your.profile"
        case .reddit: return "username"
        default: return "yourhandle"
        }
    }
}

extension SocialPlatform {
    /// Where a handle points, built from a per-platform template — never
    /// from stored text. A handle is an account name, not a URL, so the
    /// worst a hostile value can do is point at the wrong account on the
    /// right platform.
    ///
    /// Mirrors `SOCIAL_PLATFORMS` in the website's
    /// `src/lib/photos/socialLinks.ts` exactly, so the in-app verification
    /// page and the public one link to the same places.
    /// `SocialPlatformLinkTests` pins every shape against that table.
    func profileURL(handle: String) -> URL? {
        // Revalidated rather than trusted: this builds a tappable link out
        // of another user's data, and the check is one `allSatisfy` away.
        guard SocialLink.isValid(handle: handle) else { return nil }
        switch self {
        case .instagram: return URL(string: "https://www.instagram.com/\(handle)/")
        case .x: return URL(string: "https://x.com/\(handle)")
        case .tiktok: return URL(string: "https://www.tiktok.com/@\(handle)")
        case .youtube: return URL(string: "https://www.youtube.com/@\(handle)")
        case .linkedin: return URL(string: "https://www.linkedin.com/in/\(handle)")
        case .github: return URL(string: "https://github.com/\(handle)")
        case .reddit: return URL(string: "https://www.reddit.com/user/\(handle)")
        case .facebook: return URL(string: "https://www.facebook.com/\(handle)")
        }
    }

    /// How the handle reads on that platform — `@marina`, `u/marina`, or
    /// bare. Also mirrors the website, so the same account is written the
    /// same way in both places.
    func displayHandle(_ handle: String) -> String {
        switch self {
        case .instagram, .x, .tiktok, .youtube: return "@\(handle)"
        case .reddit: return "u/\(handle)"
        case .linkedin, .github, .facebook: return handle
        }
    }
}

/// One `{platform, handle}` entry in `users.social_links`.
///
/// The handle is stored **bare** — no `@`, no scheme, no host. That's not a
/// formatting preference: the website builds each link from its own
/// per-platform base URL and never from stored text, so a handle can't grow
/// into an arbitrary link (or a `javascript:` one) on a page that signed-out
/// strangers load. `handleCharacters` is the same set the database's
/// `is_valid_social_links()` enforces, and a value outside it fails the
/// CHECK constraint — which would reject the *whole* user upsert, username
/// and privacy along with it. So normalise and validate before saving.
struct SocialLink: Codable, Hashable, Identifiable {
    var platform: SocialPlatform
    var handle: String

    enum CodingKeys: String, CodingKey {
        case platform
        case handle
    }

    /// Stable only within a single editing session — `social_links` is a
    /// JSON array with no per-row identity of its own, so a list editor
    /// needs something to key rows by that survives reordering and removal.
    /// `var` rather than `let` only so `Decodable` synthesis stays quiet
    /// about an immutable property it can't write.
    var id = UUID()

    init(platform: SocialPlatform, handle: String = "") {
        self.platform = platform
        self.handle = handle
    }

    static let maxCount = 5
    static let maxHandleLength = 64

    private static let handleCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
    )

    /// Trims and strips the leading `@` people type out of habit. Anything
    /// else that's still invalid afterwards is reported rather than silently
    /// mangled — quietly deleting characters out of someone's handle would
    /// produce a link that resolves to a stranger.
    static func normalize(handle: String) -> String {
        var trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("@") {
            trimmed.removeFirst()
        }
        return trimmed
    }

    static func isValid(handle: String) -> Bool {
        !handle.isEmpty
            && handle.count <= maxHandleLength
            && handle.unicodeScalars.allSatisfy { handleCharacters.contains($0) }
    }

    var isValid: Bool { Self.isValid(handle: handle) }
}

/// `users.social_links` as a whole, wrapped purely so decoding can be
/// lenient.
///
/// The reasoning is `DatabaseEnum`'s: this array is decoded as part of the
/// user row in `AppState.hydrate`, immediately after Sign in with Apple, so
/// a throw here is not a missing feature — it's nobody being able to sign
/// in. A platform added to the database's whitelist reaches every installed
/// build the moment someone saves one, long before those builds know the
/// name, so an entry this build can't read is dropped and the rest of the
/// row survives.
///
/// The cost of dropping rather than preserving: an old build that then saves
/// its profile writes the shorter list back. That's one row of a list of at
/// most five, visible in the editor before the user taps Save — against a
/// lockout, it's the right trade.
struct SocialLinks: Codable, Hashable, ExpressibleByArrayLiteral {
    var items: [SocialLink]

    init(_ items: [SocialLink] = []) {
        self.items = items
    }

    init(arrayLiteral elements: SocialLink...) {
        self.init(elements)
    }

    /// Decodes the array in one go through a wrapper whose own initialiser
    /// swallows the failure. Decoding elements one at a time from an
    /// unkeyed container can't work: a throwing `decode` doesn't advance
    /// `currentIndex`, so the retry loop never terminates.
    private struct Lenient: Decodable {
        let value: SocialLink?

        init(from decoder: Decoder) throws {
            value = try? SocialLink(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([Lenient].self)
        items = raw.compactMap(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(items)
    }
}

/// The Stripe-verified identity of an account, and the one sentence both
/// verification surfaces state it with.
///
/// Exists so the wording can't drift: `PhotoVerificationView` shows it to a
/// viewer and `VerificationPageSheet` shows the owner what will be
/// published, and those two disagreeing about what the claim says would be
/// worse than either wording being imperfect. The website composes the same
/// sentence in `page.tsx`.
struct VerifiedIdentity: Hashable {
    /// As stored — usually shouting, straight off an identity document.
    let rawName: String
    /// When Stripe last verified. Nil for anyone verified before the app
    /// started recording it.
    let verifiedAt: Date?

    /// The name as a person would write it. See `titleCased`.
    var displayName: String { Self.titleCased(rawName) }

    /// `Identity Last Verified by Stripe on {date} proving account owner is
    /// {Name}`, or nil when there's no date — the name is still true then,
    /// but the sentence wouldn't be, so callers fall back to `displayName`.
    var statement: String? {
        guard let verifiedAt else { return nil }
        return "Identity Last Verified by Stripe on \(Self.formatted(verifiedAt)) proving account owner is \(displayName)"
    }

    /// Pinned to `en_US`, not the device locale. The sentence around it is
    /// English either way, and the website hardcodes the same format
    /// (`toLocaleDateString('en-US', …)` in `verificationPhoto.ts`) — the
    /// same verification rendering two different dates on two surfaces
    /// would undermine the one thing it's asserting.
    static func formatted(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: .current)
                .month(.wide)
                .day()
                .year()
        )
    }

    /// Re-cases a name that arrived shouting.
    ///
    /// Stripe reads these off identity documents, which are usually set
    /// entirely in capitals — the live value is "JORDAN JAMES" / "FAVA".
    /// Printed beside a verified badge that reads as a database dump rather
    /// than a person.
    ///
    /// Only *fully* uppercase values are touched. Anything already carrying
    /// a lowercase letter was cased deliberately ("van der Berg",
    /// "McDonald") and is returned untouched, since re-casing it could only
    /// make it worse. Apostrophes and hyphens count as word breaks, so
    /// O'BRIEN and MARY-JANE come out right.
    ///
    /// Known limit: "MCDONALD" becomes "Mcdonald". Spotting the Mc/Mac/O'
    /// class of surname from the string alone isn't reliable — the same rule
    /// would turn "MACEY" into "MacEy" — so this stops short on purpose.
    /// Mirrors `titleCaseName` in the website's `verificationPhoto.ts`.
    static func titleCased(_ name: String) -> String {
        guard name == name.uppercased() else { return name }

        let breaks: Set<Character> = [" ", "-", "'", "\u{2019}"]
        var result = ""
        var atBoundary = true
        for character in name.lowercased() {
            result.append(atBoundary ? Character(character.uppercased()) : character)
            atBoundary = breaks.contains(character)
        }
        return result
    }
}

/// The owner-facing half of a verification page: who took the photo, and
/// what they chose to publish alongside it.
///
/// Returned by the `get_photo_owner_profile(p_photo_id)` RPC rather than
/// read from `users` — RLS there is self-only, so an app user opening
/// someone else's link sees no row at all. The RPC is security-definer and
/// granted to `authenticated` only.
///
/// Every gate lives in that function: `display_name` arrives non-nil only
/// when the owner is verified, has `show_identity` on, and is covered by the
/// `custom_verification_pages` flag; `socialLinks` is empty unless verified
/// and flagged. Nothing here is re-decided client-side, exactly as on the
/// website.
///
/// It has no privacy gate, unlike the web RPC — per the PRD, signed-in app
/// users see full contents whether the owner is `Public` or `Humans Only`.
/// That setting separates humans from the open internet, not humans from
/// each other.
struct PhotoOwnerProfile: Decodable, Hashable {
    var username: String
    var isVerified: Bool
    /// Stripe's verified name, already composed as `First Last`. Never a
    /// self-authored one — see `HumanUser`'s note on why that distinction is
    /// the whole point.
    var displayName: String?
    /// When Stripe last verified the owner. Gated identically to
    /// `displayName` by the RPC — they're stated in one sentence, so they
    /// arrive and vanish together.
    var identityVerifiedAt: Date?
    var socialLinks: SocialLinks

    enum CodingKeys: String, CodingKey {
        case username
        case isVerified = "is_verified"
        case displayName = "display_name"
        case identityVerifiedAt = "identity_verified_at"
        case socialLinks = "social_links"
    }

    /// The verified identity as one value, or nil when the owner publishes
    /// no name.
    var verifiedIdentity: VerifiedIdentity? {
        displayName.map { VerifiedIdentity(rawName: $0, verifiedAt: identityVerifiedAt) }
    }
}

/// Maps 1:1 to a row in the `users` table, minus the columns the client has
/// no business writing. Deliberately has no SSN field: identity verification
/// runs through Stripe Identity (document + selfie checks only), which never
/// collects or sends an SSN.
///
/// No phone number either, though `users.phone_number` still exists. It was
/// collected on the verify screen and then read by *nothing* — not the app,
/// not the Edge Functions, and certainly not Stripe, whose document + selfie
/// session has no phone parameter. A required field standing in front of an
/// optional step, gathering PII with no consumer, so it's gone. The column
/// (`not null default ''`) is left in place: dropping it is a separate,
/// destructive decision, and omitting the key from an upsert simply leaves
/// existing values alone.
struct HumanUser: Codable, Hashable {
    var id: UUID?
    var username: String = ""
    var profileIconIndex: Int = 0
    var privacy: PrivacyLevel = .public_
    var verificationStatus: VerificationStatus = .unverified
    var onboardingStep: OnboardingStep = .profile

    // MARK: Verification-page customization
    //
    // What a verified user chose to put on their public verification page
    // beyond the photo itself — see `VerificationPageSheet`. Both ride along
    // on the ordinary self-row upsert like everything else here, so anyone
    // can *write* them; that's fine, because neither makes a claim. The
    // claim is `verification_status`, which no client can write, and
    // `get_verification_photo()` withholds all of this unless that column
    // says `verified`.
    //
    // The user's **name** is deliberately not here. It used to be —
    // `display_first_name` / `display_last_name`, typed by the user — and
    // that was wrong: the page renders the name beside "taken by a real,
    // verified human", so a self-authored one is a claim wearing our
    // checkmark. It now comes from `users.verified_first_name` /
    // `verified_last_name`, which only `stripe-identity-webhook` can write
    // (see `UserProfileRepository.fetchVerifiedName`), and `showIdentity`
    // decides only *whether* it's shown.

    /// Opt-in, and off by default: publishing a legal name is the most
    /// identifying thing this product does, so it happens only because
    /// someone asked for it. What gets published is Stripe's verified name,
    /// never anything typed in the app.
    var showIdentity: Bool = false

    var socialLinks: SocialLinks = SocialLinks()

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case profileIconIndex = "profile_icon_index"
        case privacy
        case verificationStatus = "verification_status"
        case onboardingStep = "onboarding_step"
        case showIdentity = "show_identity"
        case socialLinks = "social_links"
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
    /// Where this photo's **signed capture** lives in the private
    /// `photo-originals` bucket — the C2PA parent ingredient of the
    /// watermarked photo at `storagePath`, kept for photo history. `nil` for
    /// photos watermarked on device, which have no separate original. Only
    /// its owner can read it; the shared photo is always `storagePath`.
    ///
    /// Optional with a default so rows and builds that predate it decode and
    /// encode unchanged (a `nil` is left out of the upsert entirely).
    var originalStoragePath: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case storagePath = "storage_path"
        case capturedAt = "captured_at"
        case verificationDeepLink = "verification_deep_link"
        case shortCode = "short_code"
        case originalStoragePath = "original_storage_path"
    }

    /// Host of the public web verification page. Must stay in step with the
    /// website's `/[photoId]` route. Not private: `VerificationPageSheet`
    /// names it when telling the user where their customizations show up,
    /// and a second hardcoded copy of the host is exactly the drift this
    /// contract can't afford.
    static let webHost = "the-human-internet.com"

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

    /// Private bucket `sign-photo` writes each signed capture to. Mirrored in
    /// that Edge Function as `ORIGINALS_BUCKET`.
    static let originalsBucket = "photo-originals"

    /// Object path of a photo's signed capture in `originalsBucket`. The same
    /// `{user_id}/{photo_id}.jpg` shape as `storagePath` — `sign-photo`
    /// builds it independently from the caller's JWT and `X-Photo-Id`, so the
    /// two must stay identical.
    static func originalStoragePath(userID: UUID, photoID: UUID) -> String {
        storagePath(userID: userID, photoID: photoID)
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
