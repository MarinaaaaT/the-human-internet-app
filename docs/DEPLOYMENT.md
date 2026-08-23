# Deployment

Pushing to `main` builds the iOS app and uploads it to TestFlight. Roughly
15–20 minutes later it installs itself on the testers' phones. No Mac is
involved, which is the whole point: the loop is drivable from a phone.

```
push to main ──> GitHub Actions (macos-15) ──> fastlane beta ──> TestFlight
                        │                          │
                        │                          ├── match: read signing identity
                        │                          ├── gym:   archive + sign
                        │                          └── pilot: upload
                        └── build number = github.run_number
```

Manual runs: Actions tab → **TestFlight** → *Run workflow*. Same thing, off any
branch, without pushing.

## The moving parts

| Path | What it does |
| --- | --- |
| [`.github/workflows/testflight.yml`](../.github/workflows/testflight.yml) | Trigger, runner, Xcode pin, caching, secret plumbing |
| [`fastlane/Fastfile`](../fastlane/Fastfile) | `beta` (build + upload), `tests`, and `signing_bootstrap` lanes |
| [`fastlane/Appfile`](../fastlane/Appfile) | Bundle id + team id |
| `Gemfile` | Pins fastlane so a runner-image update can't silently change it |

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
can't do. The `beta` lane overrides that to Manual for the archive only, via
`xcargs`, so the checked-in project stays convenient to open in Xcode.

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

Six repository secrets, at Settings → Secrets and variables → Actions. None of
them are in this repo, and none should ever be pasted into a chat, a log, or a
commit.

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | Key ID of the App Store Connect API key |
| `ASC_ISSUER_ID` | Issuer ID from the same page |
| `ASC_KEY_P8` | Full contents of the `.p8`, BEGIN and END lines included |
| `MATCH_PASSWORD` | Passphrase encrypting the certs repo. Not recoverable — keep it in a password manager |
| `MATCH_GIT_URL` | HTTPS URL of the private certs repo |
| `MATCH_GIT_BASIC_AUTHORIZATION` | base64 of `username:personal-access-token` |

The App Store Connect API key is what avoids an Apple ID, a password, and 2FA
in CI. It needs the **App Manager** role: upload alone isn't enough, because
match also has to talk to the developer portal.

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

- **Xcode version mismatch.** The workflow pins Xcode 16.4. If the runner image
  drops it, the `xcode-select` step fails immediately and loudly — that's the
  intent. Bump the pin to a version the image actually has.
- **SPM resolution.** Network flake, or a dependency that moved. `c2pa-swift` is
  pre-1.0 and ships a prebuilt XCFramework, so it is the likeliest to break.
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
