# C2PA signing

All C2PA signing happens **server-side**. `RemotePhotoSigner` sends the
watermarked JPEG to the `sign-photo` Supabase Edge Function, which checks
the caller's JWT and forwards the bytes to an AWS Lambda that signs with a
key held in **AWS KMS** — never in this repo, the app bundle, or Supabase.
See `aws-signing-lambda/` in the sibling `the-human-internet-backend` repo
and the Notion pages under The Human Internet → Technical Architecture and
Docs for the full design.

There is no on-device fallback. This folder used to hold `PhotoSigner` and
a bundled dev certificate + private key for signing on the phone, selected
by the `aws_server_side_signing` feature flag; the path, the flag and the
key were all removed on 2026-09-23. A real production signing key must never
ship client-side, and a second signer was one more place for the capture
claim to drift.

The one deliberate exception is the developer tools' **Skip C2PA
verification** switch (admin-only, per-device — see
`AppState.isC2PASigningSkipped`), which uploads photos with no manifest at
all for testing.

## What's here

- `RemotePhotoSigner.swift` — the Edge Function call.
- `C2PAManifestReader.swift` — reads a manifest back out of a signed JPEG.
  Used by `RemotePhotoSignerTests`; it lives in the app target because a
  test target can't re-link the `C2PA` package product the app already
  links.

## Trust

The Lambda's certificate is still a self-issued dev chain, not a C2PA Trust
List certificate — getting one requires completing the C2PA Conformance
Program first, with no shortcut. Manifests are real and internally
verifiable (genuine hash binding, genuine tamper evidence), but a
third-party checker shows "signed, not on the Trust List" rather than a
green check.
