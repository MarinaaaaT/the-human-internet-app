# The Human Internet — iOS App

Native SwiftUI app for "the human network" — photo verification proving a photo was captured live by a real human. See the Notion pages under "The Human Internet" > "MVP Idea" for the full product spec (MVP Product Requirements, Technical Design Doc).

**This repo is the iOS app only.** There's a separate `the-human-internet` GitHub repo (not this one) that will hold the Next.js website (marketing pages + the signed-out web verification pages at `the-human-internet.com/{id}`). That repo hasn't been touched from here.

## Repo layout (easy to get lost in — three nested levels)

```
the-human-internet-app/              <- repo root, CLAUDE.md lives here
  Info.plist                          <- manually authored, see "Info.plist gotcha" below
  the-human-internet/                 <- Xcode project root (.xcodeproj lives here)
    the-human-internet.xcodeproj
    the-human-internet/               <- actual app source (this is the Xcode "synced group")
      Onboarding/  Camera/  Profile/  Settings/  Sharing/  Root/  Auth/  Supabase/
      DesignSystem/  Models/  Assets.xcassets/
    the-human-internetTests/
    the-human-internetUITests/
```

Xcode 16's synced-folder groups mean any `.swift` file dropped into the right subfolder under the inner `the-human-internet/` is picked up automatically — no `.pbxproj` editing needed for new source files. Editing build settings, package dependencies, capabilities, or Info.plist *does* require careful `.pbxproj` edits (all done by hand so far, always back up the file first).

## Stack

- SwiftUI, iOS 18.5 deployment target, Swift 5
- Supabase (project **"The Human Internet"**, id `xpjkgngifffzdaikjakw`, org has more) — Auth, Postgres, Storage
- Sign in with Apple (`AuthenticationServices` + `supabase.auth.signInWithIdToken`) — the *only* auth method
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
- **Camera tab**: "capture" uploads a single bundled stand-in image (`Assets.xcassets/CaptureStandIn.imageset`, a real HEIC photo the user supplied) to Supabase Storage — **not** `PhotosPicker`, **not** the real photo library. Importing from the library was explicitly ruled out: it would let someone upload an AI image or someone else's photo, defeating the "taken live by a human" guarantee. Real capture (AVFoundation) + C2PA integration is intentionally deferred to later work; only this one function will need to change.
- **Profile tab**: grid of the user's real uploaded photos (`RemotePhotoImage` downloads from the private bucket and decodes), tap through to a detail view (Preview / Share buttons).
- **Settings**: edit username (live uniqueness check against a DB constraint, friendly conflict error), edit privacy, verification-status info sheet, **Log Out** (confirmation dialog → `AppState.signOut()` → back to Welcome).
- **Sharing**: share sheet UI and a "Preview as fellow human / unknown lurker" picker — UI only, the share icons don't yet integrate with real platforms and preview-as doesn't yet render differently.
- **Deep linking**: tapping `thehumaninternet://photo/{id}` (or `xcrun simctl openurl <udid> "thehumaninternet://photo/{id}"` for testing) opens `PhotoVerificationView` as a `fullScreenCover` from `RootView`, over whatever's currently on screen. Dismissing just dismisses — the link has to be tapped again to reopen it (matches the product spec exactly).

## Database (Supabase project `xpjkgngifffzdaikjakw`)

- **`public.users`**: `id` (= `auth.users.id`), `username` (unique index, case-insensitive, only enforced once non-empty), `profile_icon_index`, `phone_number`, `privacy`, `verification_status`, `onboarding_step`, `created_at`. RLS: a user can only read/write their own row. **No SSN column exists anywhere — never add one.**
- **`public.photos`**: `id`, `user_id`, `storage_path`, `captured_at`. **No privacy column** — per the PRD, signed-in app users see full photo contents regardless of Public/Humans Only; only the (unbuilt) signed-out web page differentiates by privacy, and it would join to `users.privacy` rather than duplicating it per-photo. RLS: any authenticated user can read any row; only the owner can write.
- **Storage bucket `photos`** (private, not Storage's own public/private toggle — access is governed entirely by the RLS policies below since visibility could depend on data that changes after upload): any authenticated user can read any object; only the owner can write. Object paths are `{user_id}/{photo_id}.jpg`, **both lowercased** — Swift's `UUID().uuidString` is uppercase, Postgres renders `auth.uid()::text` lowercase, and a case-sensitive text comparison in the original RLS policy silently rejected every upload until this was caught and fixed (policy now casts to `uuid` for a type-correct comparison, and the client also lowercases defensively).

## Known gaps / next steps (from the PRD, roughly in likely order)

1. Real camera capture (AVFoundation) + C2PA integration — explicitly deferred by the user.
2. Prove identity verification — fully stubbed; `verification_status` never actually becomes `"verified"` anywhere yet.
3. Universal Links — needs the separate website repo deployed with `apple-app-site-association`, plus an Associated Domains entitlement swap (currently `com.apple.developer.applesignin` only).
4. The signed-out web verification page itself — separate repo, not started from here.
5. Real native share integration for the share sheet icons.
6. Explicitly Phase 2 per the PRD, not in scope yet: followers/following, per-photo privacy, imported photos, Android, community believability scoring.

## Dev/testing notes for whoever picks this up

- **iOS Simulator tap coordinates are device *points* (402×874 for iPhone 16 Pro), not screenshot pixels** — screenshots render at a different scale than the point space the `control` tool's `tap` action expects. Miscalculating this wastes a lot of turns; if automated taps keep missing, it's faster to just ask the user to tap manually than to keep guessing.
- **DerivedData's folder hash can change** when project build settings change significantly (this happened after the Info.plist rework) — re-check the actual path via `xcodebuild -showBuildSettings` rather than assuming a previously-used path is still current; a stale path will make a fixed bug look unfixed.
- **`GENERATE_INFOPLIST_FILE=YES` + `INFOPLIST_FILE` "partial plist merge"** (a documented Xcode feature) did not actually merge custom keys in for this project/Xcode version — had to switch to a fully manual `Info.plist` with `GENERATE_INFOPLIST_FILE=NO` and every key (including the ones that used to be `INFOPLIST_KEY_*` build settings) written out by hand. That's why `Info.plist` exists at the repo root as a real file.
- **Git push needs credentials this sandboxed session doesn't have.** Commits get made locally; run `git push origin main` from your own terminal or Xcode.
- Config already done in Xcode/Supabase dashboards (not from this session, or done by the user mid-session): Sign in with Apple capability + entitlement, `DEVELOPMENT_TEAM` set, Apple provider configured in Supabase Auth, `supabase-swift` SPM package added (had to manually add the missing umbrella `Supabase` product — the picker only added the five sub-libraries).
