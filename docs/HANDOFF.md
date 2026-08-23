# Handoff: TestFlight pipeline is live and green

Read `CLAUDE.md` first — it's thorough and current.

**Plan of record:** Notion, "🚀 Setting up the app deployment pipeline" (`3c35d773cd2f8099848dd8c9367d1117`, https://app.notion.com/p/Setting-up-the-app-deployment-pipeline-3c35d773cd2f8099848dd8c9367d1117), under The Human Internet → Technical Architecture and Docs → Infrastructure Diagrams. All phases (0–5) are functionally done as of this session; the Notion checkboxes themselves haven't been updated to match — do that before trusting them again.

## Current state

`main` builds and uploads to TestFlight on every push, and manually via Actions tab → **TestFlight** → *Run workflow*. First fully green run: `beta`, 4m14s, uploaded successfully to App Store Connect (App `6804428894`). Confirmed by reading the actual log line (`Successfully uploaded package to App Store Connect`), not just the green checkmark.

Green again on `main` as of `d10974b` (run 32653781025, 4m23s) after the C2PA min-OS work below — three runs went red in between, so don't read the earlier green as covering everything since.

**Two things still need real content before this is release-ready, not pipeline-ready:**

1. **App icon is a placeholder.** `AppIcon.appiconset` had zero actual image files before this session — Apple was rejecting every upload for a missing icon. Generated a simple placeholder (dark navy background, pink capsule+rounded-rect mark, matching `DesignSystem/Theme.swift` / `BrandMark.swift`) just to unblock the pipeline. A branding consultant is making real logos — swap `AppIcon-1024.png` / `-dark.png` / `-tinted.png` in `Assets.xcassets/AppIcon.appiconset/` for the real ones when they land; `Contents.json` already points at those three filenames, so dropping in same-named replacements is enough.
2. **Internal Testing group** in App Store Connect still needs both testers added (`docs/DEPLOYMENT.md` first-time-setup step 8) before anyone can actually install the build that's now sitting in TestFlight processing.

## Fixes made this session getting `beta` from red to green, in order hit

Useful if a fresh checkout or a secrets rotation ever reproduces one of these — each was a distinct failure, not guesswork:

1. **`ASC_KEY_P8` must be base64, not raw PEM.** A multi-line `.p8` pasted into a GitHub secret loses real newlines in transit often enough that OpenSSL fails deep in fastlane's spaceship dependency with an opaque `invalid curve name` rather than a clear parse error — a known fastlane/OpenSSL interaction (fastlane/fastlane#20553). Fixed in `asc_api_key` (`fastlane/Fastfile`): `is_key_content_base64: true`. Generate the secret with `base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '[:space:]'`.
2. **The six secrets were configured on the wrong repo** (the private certs repo, not `the-human-internet-app`) for a while — the workflow's env block silently resolved them all to empty strings rather than erroring, which produced the exact same `invalid curve name` failure and cost real time to tell apart from #1. `gh secret list -R MarinaaaaT/the-human-internet-app` is the fast way to check they're actually there.
3. **Unscoped `xcargs` signing overrides break SPM package targets.** Passing `CODE_SIGN_STYLE=Manual` etc. bare applies it to every target xcodebuild touches, including dependency targets like swift-crypto's `CCryptoBoringSSL`, which explicitly don't support having a provisioning profile assigned at all and fail the archive if one is forced on. Scoping to `SCHEME:SETTING=` fixed that specific error, but exposed —
4. **`xcargs` manual-signing overrides are unreliable on Xcode 16's archive preflight**, full stop — even correctly scoped, xcodebuild could report "No profiles ... were found" despite `match` installing a matching profile seconds earlier (fastlane/fastlane#18352). Replaced with `update_code_signing_settings` (writes the settings directly into `project.pbxproj` before `build_app` runs instead of passing them as command-line args), scoped to `targets: [SCHEME]` and `build_configurations: ["Release"]`. This is what fastlane's own codesigning guide recommends for CI and is the fix that actually stuck — don't revert to `xcargs` for this.
5. **App Store Connect now requires the iOS 26 SDK.** The workflow was pinned to Xcode 16.4 (iOS 18.5 SDK); upload was rejected outright with "All iOS and iPadOS apps must be built with the iOS 26 SDK or later." This surfaces very late — after a full successful archive/sign/export, at the upload step — and reads like a validation problem, not a toolchain one. Bumped the pin to Xcode 26.3 (`.github/workflows/testflight.yml`), which the `macos-15` runner already has installed — no `runs-on` change needed. If this happens again, check `gh api repos/actions/runner-images/contents/images/macos/macos-15-arm64-Readme.md` for what's actually on the image before assuming a runner upgrade is required.
6. **Missing app icon** — see "Current state" above.
7. **`ITMS-90208`: the vendored `C2PAC.framework` declares `MinimumOSVersion 16.0` in its `Info.plist` while its binary's `LC_BUILD_VERSION` says `minos 18.5`.** An upstream `c2pa-swift` 0.0.12 packaging defect, not a project setting — App Store Connect validates embedded frameworks and rejects the upload once it reconciles the two. Fixed by `fix_c2pa_framework_min_os_version` in the Fastfile. **The first attempt patched the exported `.ipa` and made things worse**: editing any file inside an already-signed bundle invalidates the signature, turning the rejection into "Missing or invalid signature. The bundle ... is not signed using an Apple submission certificate." The patch has to run on the resolved SPM artifact *before* `build_app` archives — which is why the lane now resolves packages explicitly and then passes `skip_package_dependencies_resolution: true`. Full write-up in `docs/DEPLOYMENT.md`.
8. **Raw `sh`/Ruby in a Fastfile runs from `fastlane/`, not the repo root** (a documented fastlane quirk) — while fastlane *actions* resolve from the root. The min-OS patch silently looked for `fastlane/SourcePackages/...` and always reported the artifact missing. Hence `REPO_ROOT` at the top of the Fastfile: use it for any `sh`/`File`/`Dir` path, and plain repo-relative paths for action arguments.

Signing chain, confirmed working: `match(readonly: false)` (the `signing_bootstrap` lane, run once via manual `workflow_dispatch`) minted a distribution cert (`Apple Distribution: Marina Tassi`, team `9HP4Y79QFR`) and an App Store profile into the private certs repo. `beta`'s `match(readonly: true)` reads both back correctly on every run since.

## Three things that will still bite you

1. **Build number.** `CURRENT_PROJECT_VERSION` is still `1` in `project.pbxproj` — deliberately. The `beta` lane overrides it at archive time via `xcargs` with `github.run_number`. **Re-running a failed workflow reuses its run number, so a run that already uploaded can't be re-run — push a new commit instead**, or use manual `workflow_dispatch` (which also consumes a fresh run number).
2. **Never add a `pull_request` trigger** to `testflight.yml`, and above all not `pull_request_target`. The repo is public and the job holds signing secrets. Three guards exist (no PR trigger, GitHub's fork default, a `github.repository` `if:`). Reasoning is in a comment at the top of the file.
3. **`RemotePhotoSignerTests` fails with `sessionMissing`** — by design, unrelated to any of the above. Needs a real signed-in Supabase session in the simulator's Keychain. **26/28 unit tests pass; those 2 are the only failures and are not a regression.** Don't "fix" them.

## Housekeeping still open

- **Old bundle id `com.marina.the-human-internet`** is still listed in Supabase Auth → Apple provider → Client IDs. Remove once confident no old-identifier build is running anywhere.
- **Notion plan-of-record checkboxes** don't reflect that phases 3–5 are actually done — update before relying on them to judge status again.
- **`gh` auth works from this session** (`gh auth status` is green, `MarinaaaaT` account, `repo` scope) — `gh workflow run` / `gh run view` / `gh secret list` / `gh pr create` all work directly. **`git push` works too, but only over SSH**: the `origin` remote is HTTPS and fails with "could not read Username ... Device not configured", while `git push git@github.com:MarinaaaaT/the-human-internet-app.git <branch>` succeeds (verified 2026-08-23, pushing `claude/stripe-host-allowlist-tests`). Earlier notes here said pushing was impossible — that was the HTTPS remote, not pushing as such.

Marina does manual/device testing; Claude runs the automated tests.
