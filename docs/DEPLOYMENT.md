# Deployment

Pushing to `main` builds the iOS app and uploads it to TestFlight. Roughly
15–20 minutes later it installs itself on the testers' phones. No Mac is
involved, which is the whole point: the loop is drivable from a phone.

```
push to main ──> GitHub Actions (macos-15) ──> fastlane beta ──> TestFlight
                        │                          │
                        │                          ├── match:  read signing identity
                        │                          ├── resolve SPM + patch C2PAC min-OS
                        │                          ├── gym:    archive + sign
                        │                          └── pilot:  upload
                        │
                        └── build number = github.run_number   ──> Discord (always)
```

Manual runs: Actions tab → **TestFlight** → *Run workflow*. Same thing, off any
branch, without pushing.

## The moving parts

| Path | What it does |
| --- | --- |
| [`.github/workflows/testflight.yml`](../.github/workflows/testflight.yml) | Trigger, runner, Xcode pin, caching, secret plumbing |
| [`fastlane/Fastfile`](../fastlane/Fastfile) | `beta` (build + upload), `tests`, and `signing_bootstrap` lanes |
| [`fastlane/Appfile`](../fastlane/Appfile) | Bundle id + team id |
| `Gemfile` | Declares fastlane for `bundler-cache`. **Unpinned, and no `Gemfile.lock` is committed** — see below |

The `Gemfile` is `gem "fastlane"` with no version constraint and there is no
committed `Gemfile.lock`, so `bundler-cache: true` resolves fastlane fresh on a
cache miss and a fastlane release can change CI behaviour with no commit in
this repo. Committing a lockfile (`bundle lock`) is the fix if a build ever
goes red with no change on this side.

`the-human-internet.xcscheme` lives in the project's `xcshareddata/xcschemes/`.
It has to stay there and stay committed — Xcode's default is to write schemes
into `xcuserdata/`, which is gitignored, and a scheme CI cannot see is a scheme
CI cannot build. If a scheme ever stops being visible to CI, check the *Shared*
box in Xcode's *Manage Schemes* and commit the result.

## Identity: what signs the build

Distribution signing goes through **fastlane match**. The distribution
certificate and provisioning profile live encrypted in a separate private repo
and are only ever *read* by CI. That is what lets a runner, a Mac, and a
teammate's machine all sign as the same identity instead of each minting a new
certificate — Apple caps distribution certificates, and revoking one
invalidates every build already signed with it.

`match` runs `readonly: true` in the `beta` lane, deliberately. A routine build
must not be able to regenerate signing material.

The Xcode project itself uses **Automatic** signing, which a headless runner
can't do. The `beta` lane overrides that to Manual with
`update_code_signing_settings`, scoped to the app target and the `Release`
configuration, so the checked-in project stays convenient to open in Xcode.

Passing those settings as `build_app` `xcargs` instead — which an earlier
version of this lane did — is unreliable, in two separate ways. Unscoped, the
override reaches every target xcodebuild touches, including SPM dependency
targets like swift-crypto's `CCryptoBoringSSL` that don't accept a
provisioning profile at all and fail the archive if forced to. Scoped
correctly, xcodebuild's signing preflight could *still* report
"No profiles ... were found" despite match having installed a matching profile
seconds earlier (fastlane/fastlane#18352). Writing the settings into
`project.pbxproj` before the archive is what fastlane's own codesigning guide
recommends for CI, and is the fix that stuck — **don't revert to `xcargs` for
signing.**

## The C2PA framework min-OS patch

`c2pa-swift` 0.0.12 vendors a `C2PAC.framework` that is internally
inconsistent: its `Info.plist` declares `MinimumOSVersion 16.0`, but the
compiled binary's `LC_BUILD_VERSION` says `minos 18.5`. App Store Connect
validates the embedded frameworks, not just our own deployment target, and
rejects the upload with **ITMS-90208** once it tries to reconcile the two.
This is an upstream packaging defect — the framework is prebuilt and never
recompiled here, so no project setting of ours can fix it.

The `beta` lane works around it in `fix_c2pa_framework_min_os_version`, and
the *ordering* is load-bearing:

1. `xcodebuild -resolvePackageDependencies` runs explicitly, ahead of
   `build_app`, so the artifact is on disk to patch.
2. `PlistBuddy` rewrites `MinimumOSVersion` to `18.5` on the `ios-arm64`
   slice — the only one that ends up in an app-store archive.
3. `build_app` runs with `skip_package_dependencies_resolution: true`, so it
   can't re-resolve and re-extract over the patch.

**Patching the built output instead does not work.** An earlier version
patched the exported `.ipa`; modifying any file inside an already-signed
bundle invalidates its signature, and the upload failed with "Missing or
invalid signature. The bundle ... is not signed using an Apple submission
certificate." The patch has to land before Xcode embeds and signs the
framework.

The helper hard-fails if the artifact isn't at the expected path, which is the
intended signal that a `c2pa-swift` bump needs this re-checked — including
checking whether upstream has fixed it and the patch can simply be deleted.

## Build numbers

`CURRENT_PROJECT_VERSION` is hardcoded to `1` in `project.pbxproj` so local
Xcode builds produce a valid `CFBundleVersion`. CI overrides it at archive time
with `github.run_number`, which is monotonic and never reused — App Store
Connect rejects a duplicate build number outright.

One consequence worth knowing: **re-running a failed workflow reuses its run
number.** If a run got as far as uploading and then failed, re-running it
uploads a duplicate build number and Apple rejects it. Push a new commit
instead. `MARKETING_VERSION` (the user-visible `1.0`) is still edited by hand.

## Secrets

Six required repository secrets, plus one optional, at Settings → Secrets and
variables → Actions. None of them are in this repo, and none should ever be
pasted into a chat, a log, or a commit.

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | Key ID of the App Store Connect API key |
| `ASC_ISSUER_ID` | Issuer ID from the same page |
| `ASC_KEY_P8` | **Base64-encoded** contents of the `.p8` — `base64 -i AuthKey_XXXXXXXXXX.p8 \| tr -d '\n'`, not the raw PEM text. A raw multi-line PEM pasted into a GitHub secret can lose its line breaks in transit, which fails deep inside fastlane's spaceship dependency with an opaque `OpenSSL::PKey::ECError: invalid curve name` rather than a clear parse error |
| `MATCH_PASSWORD` | Passphrase encrypting the certs repo. Not recoverable — keep it in a password manager |
| `MATCH_GIT_URL` | HTTPS URL of the private certs repo |
| `MATCH_GIT_BASIC_AUTHORIZATION` | base64 of `username:personal-access-token` |
| `DISCORD_WEBHOOK_URL` (optional) | A Discord channel webhook URL (channel → Edit Channel → Integrations → Webhooks). If unset, the notify step just skips itself — everything else still runs |

The App Store Connect API key is what avoids an Apple ID, a password, and 2FA
in CI. It needs the **App Manager** role: upload alone isn't enough, because
match also has to talk to the developer portal.

## Discord notifications

The last step of the job posts a build result (✅/❌/⏹️, lane, commit, actor,
link to the run) to a Discord channel via a plain `curl` to a webhook URL —
deliberately not a marketplace Discord action, since this repo is public and
the job already holds signing secrets; a chat notification isn't worth adding
a new third-party action to that trust boundary. Fires on every run
(`if: always()`), success or failure, for both `push` and `workflow_dispatch`.

To wire it up: in Discord, go to the target channel → **Edit Channel** →
**Integrations** → **Webhooks** → **New Webhook**, copy its URL, and set it as
the `DISCORD_WEBHOOK_URL` repo secret. Nothing else to configure.

### Why this workflow can't run on a pull request

The repo is **public**, and this workflow holds the distribution certificate's
keys. So it triggers only on `push` to `main` and `workflow_dispatch` — there is
no `pull_request` trigger, and specifically no `pull_request_target`, which
would run with secrets available while checking out a contributor's branch. A
`if: github.repository == …` guard keeps it inert in forks as well. Do not add a
`pull_request` trigger to this file. If PR-time CI is wanted, add a *separate*
workflow that runs the `tests` lane and touches no secrets.

## First-time setup

Already done once; recorded here in case it has to be redone.

1. **Apple Developer Program** membership active. Team ID `9HP4Y79QFR`.
2. **App ID** registered at `developer.apple.com` for `com.thehumaninternet.app`,
   with the **Sign in with Apple** capability — the app's entitlements require it.
3. **App Store Connect app record** created against that bundle id.
4. **App Store Connect API key** (App Manager). The `.p8` downloads exactly
   once; losing it means revoking and starting over.
5. **Private certs repo** for match, plus a PAT with `repo` scope so CI can read it.
6. **The six secrets** above.
7. **Signing bootstrap** — one run of match in create mode to mint the
   certificate and profile and push them, encrypted, to the certs repo. This is
   the step that normally requires Keychain Access on a Mac; match generates the
   signing request itself using the API key. Lives as the `signing_bootstrap`
   lane in the Fastfile — `readonly: false`, so it creates signing material if
   the certs repo has none yet, or just reads it if it does, meaning it's safe
   to re-run later (e.g. after a capability change forces a new profile).

   Run it once via the Actions tab → **TestFlight** → *Run workflow* → set
   **lane** to `signing_bootstrap`, or locally with the six secrets exported:
   `bundle exec fastlane signing_bootstrap`. **Never** wire this lane to the
   `push` trigger — a routine build must stay on the readonly `beta` lane.
8. **Internal Testing group** in TestFlight with both testers. Internal testers
   skip Beta App Review, so a green build is installable within minutes.
   Enabling automatic updates in the TestFlight app completes the loop.

## When a build goes red

Job logs are readable from the Actions tab (or `gh run view --log-failed`), and
the workflow uploads gym/fastlane logs as an artifact on failure. The usual
suspects, in rough order of likelihood:

- **Xcode version mismatch.** The workflow pins Xcode 26.3. If the runner image
  drops it, the `xcode-select` step fails immediately and loudly — that's the
  intent. Bump the pin to a version the image actually has. Don't bump it
  below whatever SDK App Store Connect currently requires at upload time —
  that rejection surfaces late, at `upload_to_testflight`, after a full
  archive, and reads as an unrelated validation error rather than a version
  problem.
- **SPM resolution.** Network flake, or a dependency that moved. `c2pa-swift` is
  pre-1.0 and ships a prebuilt XCFramework, so it is the likeliest to break.
- **`ITMS-90208` at upload**, or `fix_c2pa_framework_min_os_version` hard-failing
  on a missing artifact path. Both mean the C2PA framework patch above needs
  re-checking against the current `c2pa-swift` version. Like the SDK rejection,
  ITMS-90208 surfaces only after a full successful archive.
- **Profile / entitlement mismatch.** Usually means the App ID is missing a
  capability the entitlements file asks for (Sign in with Apple), or the profile
  predates a capability change. Re-run the bootstrap to regenerate the profile.
- **Duplicate build number.** See the build-numbers section above — push, don't
  re-run.

## What still genuinely needs a Mac

- **Nothing routine.**
- **Camera work can't be verified in the Simulator**, which has no camera.
  TestFlight actually improves this: real builds reach a real camera with no cable.
- **Deep Xcode work** — build settings, SPM packages, capabilities — means
  hand-editing `project.pbxproj`, which realistically wants Xcode. See the repo
  `CLAUDE.md` for the conventions that apply when doing so by hand.
