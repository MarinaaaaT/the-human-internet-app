# C2PA dev signing material

`C2PADevCertificate.pem` is a two-cert chain (leaf + local dev CA) and
`C2PADevPrivateKey.pem` is the leaf's P-256 key — **not** a production C2PA
Trust List certificate. Getting one of those requires completing the C2PA
Conformance Program first; there's no shortcut, not even through a CA's free
tier.

Manifests signed with this dev key are real and internally verifiable
(genuine hash binding, genuine tamper evidence) but won't chain to a
publicly-trusted authority — a third-party C2PA checker will show "signed,
not on the Trust List" rather than a green checkmark.

It's safe for this key to live in the app bundle specifically *because* it
isn't a real trust anchor: a leaked dev key can only forge equally-untrusted
manifests. **A real production signing key must never ship client-side** —
signing should move server-side rather than just swapping these two files
in place.

That move has happened: it's gated behind the `aws_server_side_signing`
feature flag, which is **currently on** (see `FeatureFlagRepository.swift`
and `PhotoUploadQueue.drive()`, which picks the signer per photo; the flag
defaults to *off* — this on-device path — if flags can't be read). The key
itself lives in **AWS KMS**, never in this repo, the app bundle, or
Supabase — see `aws-signing-lambda/` in the sibling
`the-human-internet-backend` repo (it moved out of this one on 2026-08-14)
and the Notion pages under The Human Internet → Technical Architecture and
Docs for the full design and setup checklist. The
Supabase `sign-photo` Edge Function is only the identity-checking front
door (verifies the caller's JWT, same as `stripe-identity-session`); it
forwards to the Lambda over IAM auth rather than holding the key itself.

## Regenerating

Two non-obvious constraints, both of which fail only at *signing* time with
opaque errors, so they're easy to get wrong:

1. **The key must be PKCS#8** (`BEGIN PRIVATE KEY`), which is what `genpkey`
   emits. `openssl ecparam -genkey` emits SEC1 (`BEGIN EC PRIVATE KEY`) and
   fails with `unexpected PEM type label`. Both are valid, common PEM forms
   for an EC key and most openssl examples online use `ecparam` — so this
   one bites easily.
2. **The signing cert must not be self-signed.** c2pa-swift rejects it
   outright (`the certificate was self-signed`). It needs a leaf issued by a
   CA, with `CA:FALSE`, EKU `emailProtection`, and key usage
   `digitalSignature, nonRepudiation` — all critical. These extensions match
   c2pa-swift's own test fixture (`TestShared/Resources/es256_certs.pem`).

```bash
cat > leaf_ext.cnf <<'EOF'
basicConstraints = critical, CA:FALSE
extendedKeyUsage = critical, emailProtection
keyUsage = critical, digitalSignature, nonRepudiation
subjectKeyIdentifier = hash
EOF

# Local dev CA (self-signed is fine for the CA — it's the leaf that can't be)
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out ca_key.pem
openssl req -new -x509 -key ca_key.pem -out ca_cert.pem -days 3650 \
  -subj "/C=US/O=The Human Internet/OU=FOR DEVELOPMENT ONLY/CN=The Human Internet Dev CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

# Leaf signing key + CSR
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out C2PADevPrivateKey.pem
openssl req -new -key C2PADevPrivateKey.pem -out leaf.csr \
  -subj "/C=US/O=The Human Internet/OU=FOR DEVELOPMENT ONLY/CN=The Human Internet Dev Signer"

# CA signs the leaf; chain is leaf first, then CA
openssl x509 -req -in leaf.csr -CA ca_cert.pem -CAkey ca_key.pem -CAcreateserial \
  -out leaf_cert.pem -days 3650 -extfile leaf_ext.cnf
cat leaf_cert.pem ca_cert.pem > C2PADevCertificate.pem
```

The CA's private key is deliberately *not* kept in the repo — nothing at
runtime needs it, and the chain is regenerated wholesale by the recipe above.
