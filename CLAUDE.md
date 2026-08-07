# The Human Internet — iOS App

Native SwiftUI app for "the human internet" — photo verification proving a photo was captured live by a real human. See the Notion pages under "The Human Internet" > "MVP Idea" for the full product spec (MVP Product Requirements, Technical Design Doc).

> The product was renamed from "the human network" to **"the human internet"** on 2026-08-06, across both the app/site and Notion.
>
> Treat the **Technical Design Doc in Notion as stale**: it describes passkey auth, a three-tier privacy model, and a two-domain split — none of which is what got built. The live schema and this file are the source of truth.

**This repo is the iOS app only.** The Next.js website is a separate repo, cloned locally at `../the-human-internet-website/the-human-internet/`. It's built and deployed on Vercel: marketing pages, `/about` + `/about/verification`, and the signed-out verification page at `the-human-internet.com/{photoId}`. Both repos talk to the same Supabase project.

**The two repos share a contract:** `VerifiedPhoto.verificationURL` must match the website's `/[photoId]` route, which looks photos up by bare `photos.id`. `VerifiedPhotoLinkTests` pins it. Changing the route or the id format breaks links already shared in the wild — treat it as a public API.

## Repo layout (easy to get lost in — three nested levels)

```
the-human-internet-app/              <- repo root, CLAUDE.md lives here
  Info.plist                          <- manually authored, see "Info.plist gotcha" below
  the-human-internet/                 <- Xcode project root (.xcodeproj lives here)
    the-human-internet.xcodeproj
    the-human-internet/               <- actual app source (this is the Xcode "synced group")
      Onboarding/  Profile/  Settings/  Sharing/  Root/  Auth/  Supabase/
      DesignSystem/  Models/  Assets.xcassets/
      Camera/                         <- capture tab; Capture/ holds the AVFoundation
                                         session + the SwiftUI preview-layer bridge
      Verification/                   <- C2PA signing + the bundled dev cert (has its
                                         own README — read it before touching the certs)
    the-human-internetTests/          <- PhotoSignerTests, VerifiedPhotoLinkTests
    the-human-internetUITests/
```

Xcode 16's synced-folder groups mean any `.swift` file dropped into the right subfolder under the inner `the-human-internet/` is picked up automatically — no `.pbxproj` editing needed for new source files. Editing build settings, package dependencies, capabilities, or Info.plist *does* require careful `.pbxproj` edits (all done by hand so far, always back up the file first).

## Stack

- SwiftUI, iOS 18.5 deployment target, Swift 5
- Supabase (project **"The Human Internet"**, id `xpjkgngifffzdaikjakw`, org has more) — Auth, Postgres, Storage
- Sign in with Apple (`AuthenticationServices` + `supabase.auth.signInWithIdToken`) — the *only* auth method
- `AVFoundation` for camera capture; [`c2pa-swift`](https://github.com/contentauth/c2pa-swift) (SPM, product `C2PA`) for content-credential signing — pre-1.0, ships a prebuilt XCFramework so there's no Rust toolchain to install
- Custom URL scheme `thehumaninternet://photo/{id}` for deep links today; will swap to a real Universal Link (`applinks:the-human-internet.com`) once the website repo hosts an `apple-app-site-association` file — the in-app parsing/presentation logic is written to make that swap trivial

### Why Sign in with Apple, not passkeys
Passkeys were the original plan (matches the wireframes), but Supabase's passkey registration requires an *already-authenticated, confirmed, non-anonymous* user — which conflicts with a passkey-first signup flow with no prior account. Pivoted to Sign in with Apple, which creates-or-signs-in in one call via `signInWithIdToken`.

## Architecture pattern

- **Dumb views + one coordinator.** Views take closures and don't know about navigation or Supabase (e.g. `WelcomeView` doesn't know what `onCompletion` does). `OnboardingFlowView` is the only view that owns a `NavigationStack` + knows the step sequence.
- **Services/repositories for side effects**: `AppleAuthService` (Auth/), `UserProfileRepository` + `PhotoRepository` + `SupabaseClient` (Supabase/) — enums or `@Observable` classes, never touched directly by leaf views.
- **One `AppState`** (`@Observable`, injected via `.environment`) holds `user`, `photos`, `isOnboarded`, `deepLinkedPhoto`. No per-screen view models — added only if a screen's local `@State` actually gets unwieldy.
- **`AppState.hydrate(userID:)` is the single source of truth** for "identity is authenticated → here's their profile + photos + whether onboarding is done." Both `RootView` (cold launch, session restored from Keychain) and `OnboardingFlowView` (fresh sign-in) call it. These *used to* be two separate copies of this logic and drifted apart (only one fetched photos, neither special-cased a returning fully-onboarded user) — fixed by collapsing into one method. If you touch sign-in/session logic, keep it that way.
- **`DesignSystem/`** is the only place styling lives (`Theme.swift` colors, `Components.swift` buttons/fields, `RemotePhotoImage.swift` for loading photos from Storage).

## What's built (MVP scaffold, functional end-to-end)

- **Onboarding**: Welcome (Sign in with Apple) → Profile setup (username, checked for case-insensitive uniqueness) → Identity verification (phone + SSN last-4) → Welcome/take-first-photo → main app. Progress persists to `users.onboarding_step` after every step, so force-quitting mid-onboarding resumes at the right screen on relaunch. **SSN last-4 is validated locally and never sent anywhere** — no field for it exists in any model or table, by design (explicit user requirement).
- **Camera tab**: real `AVFoundation` capture (`Camera/Capture/CameraSession.swift` + `CameraPreviewView.swift`), C2PA-signed by `Verification/PhotoSigner.swift` before upload to Supabase Storage. **Not** `PhotosPicker`, **not** the photo library — importing was explicitly ruled out: it would let someone upload an AI image or someone else's photo, defeating the "taken live by a human" guarantee. `Assets.xcassets/CaptureStandIn.imageset` is the retired stand-in, now unused. The tab has three states: live preview, permission-denied (with a Settings deep link), and no-camera-available.
- **Profile tab**: grid of the user's real uploaded photos (`RemotePhotoImage` downloads from the private bucket and decodes), tap through to a detail view (Preview / Share buttons).
- **Settings**: edit username (live uniqueness check against a DB constraint, friendly conflict error), edit privacy, verification-status info sheet, **Log Out** (confirmation dialog → `AppState.signOut()` → back to Welcome).
- **Sharing**: **Copy Link** works — it copies `VerifiedPhoto.verificationURL` (the public `https://` web link that resolves signed-out), deliberately *not* the `thehumaninternet://` deep link, which only opens for people who already have the app. The other share targets (Instagram, TikTok, …) and the "Preview as fellow human / unknown lurker" picker are still UI-only.
- **Deep linking**: tapping `thehumaninternet://photo/{id}` (or `xcrun simctl openurl <udid> "thehumaninternet://photo/{id}"` for testing) opens `PhotoVerificationView` as a `fullScreenCover` from `RootView`, over whatever's currently on screen. Dismissing just dismisses — the link has to be tapped again to reopen it (matches the product spec exactly).

## C2PA signing

Every captured photo gets a real, embedded C2PA manifest before upload (`Verification/PhotoSigner.swift`), asserting `c2pa.created` with `digitalSourceType=digitalCapture` — "a real camera took this", the claim the whole product rests on. Verified working end-to-end on a physical device: the uploaded JPEG bytes contain the manifest, `validation_state` is `Valid`, and hash bindings hold.

**It is signed with a bundled self-issued dev certificate**, so manifests report `signingCredential.untrusted` — a third-party C2PA checker shows "signed, not on the Trust List" rather than a green check. A production cert requires completing the C2PA Conformance Program first (no shortcut exists, not even via a CA's free tier). **When that lands, do not just swap the PEMs**: a real signing key must never ship in an app bundle — move signing server-side. Full rationale + the cert regeneration recipe in `the-human-internet/Verification/README.md`.

Three non-obvious things, all of which fail *only* at signing time with opaque errors:

1. **Key must be PKCS#8** (`openssl genpkey`, `BEGIN PRIVATE KEY`). `ecparam -genkey` emits SEC1 and fails with `unexpected PEM type label`. Most openssl examples online use `ecparam`.
2. **The signing cert must not be self-signed.** c2pa-swift rejects it outright; it needs a CA-issued leaf with `CA:FALSE` + `emailProtection` EKU + `digitalSignature,nonRepudiation` key usage, all critical.
3. **`digitalSourceType` must be camelCase in the manifest JSON.** Swift's `Action` type encodes `digital_source_type`, but the C2PA **v2** actions assertion expects `digitalSourceType`; the v2 parser silently drops the snake_case form, degrading the claim to a bare `c2pa.created`. Three separate library APIs (`ManifestDefinition.created`, `Builder.setIntent`, `Builder.addAction`) all hit this — which is why the manifest JSON is written by hand. Verify by reading the raw `assertion_store`, not `Reader.json()`, which is a summary view that omits the field entirely.

`PhotoSignerTests` covers all of this without a camera, so it runs on the Simulator.

## Database (Supabase project `xpjkgngifffzdaikjakw`)

- **`public.users`**: `id` (= `auth.users.id`), `username` (unique index, case-insensitive, only enforced once non-empty), `profile_icon_index`, `phone_number`, `privacy`, `verification_status`, `onboarding_step`, `created_at`. RLS: a user can only read/write their own row. **No SSN column exists anywhere — never add one.**
- **`public.photos`**: `id`, `user_id`, `storage_path`, `captured_at`, `verification_deep_link`. **No privacy column** — per the PRD, signed-in app users see full photo contents regardless of Public/Humans Only; only the signed-out web page differentiates by privacy, and it joins to `users.privacy` rather than duplicating it per-photo. RLS: any authenticated user can read any row; only the owner can write.
- **Storage bucket `photos`** (private, not Storage's own public/private toggle — access is governed entirely by the RLS policies below since visibility could depend on data that changes after upload): any authenticated user can read any object; only the owner can write. Object paths are `{user_id}/{photo_id}.jpg`, **both lowercased** — Swift's `UUID().uuidString` is uppercase, Postgres renders `auth.uid()::text` lowercase, and a case-sensitive text comparison in the original RLS policy silently rejected every upload until this was caught and fixed (policy now casts to `uuid` for a type-correct comparison, and the client also lowercases defensively).

### Anonymous web access (added for the verification page)

The website reads with only the publishable/anon key, so this is what makes signed-out access work — and it's deliberately narrow:

- **`get_verification_photo(p_photo_id uuid)`**, `security definer`, granted to `anon`. Returns `storage_path`/`username` **only** when the owner's privacy is `Public`, plus `captured_at` and `is_public`. Chosen over blanket anon-readable table policies specifically so nobody with the public key can *enumerate* every photo — the RPC only ever answers about one id you already hold.
- **`storage.objects`**: an `anon` SELECT policy allowing objects whose owner is `Public`, via the `is_public_photo_owner()` security-definer helper.

Two traps, both found the hard way and both silent:

- **RLS does not bypass RLS.** The storage policy's first version had an `EXISTS` subquery reading `public.users` directly — but `anon` has no SELECT rights there (self-only RLS), so the subquery saw zero rows and the policy always evaluated false. Hence the security-definer helper.
- **`storage.buckets` has its own RLS**, with no `anon` policy by default. Without one, `createSignedUrl` fails with a misleading `Object not found` before it ever reaches the object-level check.

When debugging anon access, test as the role — `set local role anon; select …` — rather than assuming a policy that *exists* actually *passes*.

## Known gaps / next steps (from the PRD, roughly in likely order)

1. **A production C2PA certificate** — blocked on the C2PA Conformance Program, which is a business/compliance process, not code. Until then manifests read as untrusted. See the C2PA section above; signing should move server-side at the same time.
2. Prove identity verification — fully stubbed; `verification_status` never actually becomes `"verified"` anywhere yet.
3. Universal Links — the website is deployed now, so this needs an `apple-app-site-association` file served from it plus an Associated Domains entitlement (currently `com.apple.developer.applesignin` only). Would let `the-human-internet.com/{id}` open the app directly instead of the custom scheme.
4. Real native share integration for the share-sheet icons (Copy Link already works).
5. Placeholder links still live on the marketing site — App Store URL, Join, step 3's CTA, and the Discord/donate/roadmap links, all centralised in the website's `src/content/site.ts`.
6. Explicitly Phase 2 per the PRD, not in scope yet: followers/following, per-photo privacy, imported photos, Android, community believability scoring.

## Dev/testing notes for whoever picks this up

- **iOS Simulator tap coordinates are device *points* (402×874 for iPhone 16 Pro), not screenshot pixels.** This bit again on 2026-08-06 and cost ~10 turns. What actually works: take a ground-truth shot with `xcrun simctl io <udid> screenshot`, which is 1206×2622 for this device — **exactly 3.0×** — and divide. The MCP screenshot tool returned stale/blank frames repeatedly; simctl never did. Better still, avoid taps: `xcrun simctl privacy <udid> grant camera <bundle-id>` for permission dialogs, `simctl pbpaste` to check a copy action, direct Supabase queries to confirm an upload. If a flow genuinely needs hands, ask the user early rather than grinding.
- **The Simulator has no camera.** Any capture path is unverifiable there and needs a physical device. `PhotoSignerTests` deliberately tests signing with a generated image so it *can* run on the Simulator.
- **Run `xcodebuild` with `-derivedDataPath /tmp/claude-derived-data`** when Xcode.app may be open. Sharing DerivedData with a live Xcode session caused a bogus `unable to load transferred PIF: … multiple references with the same GUID` (fixed only by quitting Xcode fully) and, after a half-completed `rm -rf` that Xcode had files open in, a phantom missing-framework link error that survived a clean wipe.
- **A test target must not re-link a package product its host app already links.** Adding `C2PA` to the test target's `packageProductDependencies` broke the test build with a missing-framework error. Reach the dependency through the app target via `@testable import` instead.
- **DerivedData's folder hash can change** when project build settings change significantly (this happened after the Info.plist rework) — re-check the actual path via `xcodebuild -showBuildSettings` rather than assuming a previously-used path is still current; a stale path will make a fixed bug look unfixed. Note `PRODUCT_BUNDLE_IDENTIFIER` doesn't resolve in `-showBuildSettings` output here; read `CFBundleIdentifier` from the built `.app`'s Info.plist instead.
- **`GENERATE_INFOPLIST_FILE=YES` + `INFOPLIST_FILE` "partial plist merge"** (a documented Xcode feature) did not actually merge custom keys in for this project/Xcode version — had to switch to a fully manual `Info.plist` with `GENERATE_INFOPLIST_FILE=NO` and every key (including the ones that used to be `INFOPLIST_KEY_*` build settings) written out by hand. That's why `Info.plist` exists at the repo root as a real file.
- **Git push needs credentials this sandboxed session doesn't have.** Commits get made locally; run `git push origin main` from your own terminal or Xcode.
- Config already done in Xcode/Supabase/Vercel dashboards (not from this session, or done by the user mid-session): Sign in with Apple capability + entitlement, `DEVELOPMENT_TEAM` set, Apple provider configured in Supabase Auth, `supabase-swift` SPM package added (had to manually add the missing umbrella `Supabase` product — the picker only added the five sub-libraries), and the website's Vercel env vars + Next.js framework preset.
- **`c2pa-swift` was added to `.pbxproj` by hand**, mirroring the `supabase-swift` pattern: one `XCRemoteSwiftPackageReference`, one `XCSwiftPackageProductDependency` for the `C2PA` product, a matching `PBXBuildFile`, appended to the app target's `PBXFrameworksBuildPhase` + `packageProductDependencies`, and referenced in `PBXProject.packageReferences`. Six edit sites. `plutil -lint` the file afterward — it catches a malformed edit instantly.
