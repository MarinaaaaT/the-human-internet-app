# Handoff: TestFlight deployment pipeline, Phase 4 landed (uncommitted)

Read `CLAUDE.md` first — it's thorough and current.

**Plan of record:** Notion, "🚀 Setting up the app deployment pipeline" (`3c35d773cd2f8099848dd8c9367d1117`, https://app.notion.com/p/Setting-up-the-app-deployment-pipeline-3c35d773cd2f8099848dd8c9367d1117), under The Human Internet → Technical Architecture and Docs → Infrastructure Diagrams. Phases 0–3 are ticked; 4 was implemented this session but not yet checked off there; 5–6 are open. Approach is GitHub Actions → fastlane → TestFlight.

## Git state — nothing is pushed, and Phase 4 isn't committed yet

Branch `testflight-deployment-pipeline`, two commits ahead of `origin/main`:

- `4296331` — bundle id rename
- `ee11936` — the pipeline

Plus **uncommitted working-tree changes** for Phase 4 (see below) in `fastlane/Fastfile`, `.github/workflows/testflight.yml`, `docs/DEPLOYMENT.md`, and this file.

Pushes fail from a Claude Code session (no credentials); Marina pushes from her own terminal. She was about to run `gh auth login` — **check `gh auth status` before assuming you can read Actions logs or push.** If it's authenticated, both may now work from the session.

## What landed

**Bundle id: `com.marina.the-human-internet` → `com.thehumaninternet.app`** across all six `PRODUCT_BUNDLE_IDENTIFIER` settings (tests became `…appTests` / `…appUITests`), plus the hardcoded fallback in `Logging/Log.swift:16`. `Info.plist` needed nothing — `CFBundleIdentifier` is `$(PRODUCT_BUNDLE_IDENTIFIER)`. The `thehumaninternet://` URL scheme is unchanged.

Supabase Auth → Apple provider → **Client IDs** had to gain the new id (it's the `aud` claim `signInWithIdToken` validates); done and sign-in verified against the existing account. **The old id `com.marina.the-human-internet` is still in that list** and should be removed once no old-identifier build is running anywhere.

**Phase 2, seven items:**

| File | Note |
|---|---|
| `…xcodeproj/xcshareddata/xcschemes/the-human-internet.xcscheme` | New. Was only in gitignored `xcuserdata/`; the hard CI blocker |
| `the-human-internet/Info.plist` | `ITSAppUsesNonExemptEncryption = false` |
| `fastlane/Fastfile`, `fastlane/Appfile`, `Gemfile` | `beta` + `tests` lanes |
| `.github/workflows/testflight.yml` | push-to-`main` + `workflow_dispatch` |
| `docs/DEPLOYMENT.md` | Standalone runbook |

## Three things that will bite you if you don't know them

1. **Build number.** `CURRENT_PROJECT_VERSION` is still `1` in `project.pbxproj` — deliberately. The `beta` lane overrides it at archive time via `xcargs` with `github.run_number`. Replacing it in the project would give local Xcode builds an empty `CFBundleVersion`. The Notion item says "replace the hardcoded build number" and is ticked; the implementation differs from the wording. **Consequence: re-running a failed workflow reuses its run number, so a run that already uploaded can't be re-run — push a new commit.**

2. **Never add a `pull_request` trigger** to `testflight.yml`, and above all not `pull_request_target`. The repo is public and the job holds signing secrets. Three guards exist (no PR trigger, GitHub's fork default, a `github.repository` `if:`). Reasoning is in a comment at the top of the file.

3. **`RemotePhotoSignerTests` fails with `sessionMissing`** — by design. It needs a real signed-in Supabase session in the simulator's Keychain, and the bundle-id change gave that simulator a fresh Keychain. **26/28 unit tests pass; those 2 are the only failures and are not a regression.** Don't "fix" them.

## Verification already done — don't redo it

Exported the tree as a clean checkout (no `xcuserdata`) and confirmed `xcodebuild -list` resolves the scheme. Built `Release` for `generic/platform=iOS` from that clean tree: succeeded, and the Info.plist has `com.thehumaninternet.app`, the injected `CFBundleVersion`, `1.0`, and the encryption key. Fastfile passes `ruby -c`; workflow parses as YAML.

Use `-derivedDataPath /tmp/claude-derived-data` for any `xcodebuild` — sharing DerivedData with an open Xcode breaks in confusing ways.

## What Phase 4 added (uncommitted)

- `fastlane/Fastfile`: new `signing_bootstrap` lane — `match(type: "appstore", ..., readonly: false)`. Creates the distribution cert + profile in the private certs repo if none exist yet, or just reads them if they do (so it's safe to re-run, e.g. after a capability change forces a new profile). Deliberately separate from `beta`, which stays `readonly: true`.
- `.github/workflows/testflight.yml`: `workflow_dispatch` now takes a `lane` choice input (`beta` default, or `signing_bootstrap`). Steps that only matter for a build (Xcode select, toolchain report, SPM cache) are skipped when `signing_bootstrap` is chosen. The `push` trigger is untouched and always runs `beta` — there is no way to reach `signing_bootstrap` except a manual dispatch with that input explicitly set.
- `docs/DEPLOYMENT.md`: first-time-setup step 7 and the moving-parts table updated to describe the lane and how to run it.

**Not yet executed.** Running it needs either (a) the branch pushed to GitHub plus a manual `workflow_dispatch` with `lane=signing_bootstrap` from the Actions tab (or `gh workflow run testflight.yml --ref testflight-deployment-pipeline -f lane=signing_bootstrap` once `gh auth status` is confirmed), or (b) a local run with the six `MATCH_*`/`ASC_*` secrets exported by hand. This session has neither a pushed branch nor those secrets in its environment, so it wrote the lane but could not run it.

## Next up

**Do not merge to `main` yet.** A push to `main` always runs the `beta` lane, which needs the signing material `signing_bootstrap` hasn't minted yet — it'll go red.

1. Review and commit the Phase 4 diff (it's currently just working-tree changes).
2. Push the branch (Marina, from her terminal).
3. Run `signing_bootstrap` once via manual `workflow_dispatch` (see above) to mint signing material into the certs repo.
4. **Phase 5:** first real `beta` build, expect 2–3 rounds of failures (Xcode pin is 16.4, SPM resolution, profile/entitlement mismatch).

Marina does manual/device testing; Claude runs the automated tests.
