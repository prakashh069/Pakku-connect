# ADR-004: Self-signed TLS certificate, with distinct dev and production trust strategies

**Status:** Accepted
**Date:** 2026-08-03
**Related:** [02_TDD.md §6](../02_TDD.md#6-deployment-modes-development-vs-production), [02_TDD.md §7 threat model](../02_TDD.md#7-threat-model), [ADR-002](./ADR-002-jwt-pairing.md)

## Context

The Mac and phone talk over plain LAN Wi-Fi. Call signaling — including the
ability to remotely answer/reject calls — is sensitive enough that it must
not travel in cleartext, and must not be interceptable/spoofable by another
device on the same Wi-Fi network. But this is a two-device personal pairing
app with no public DNS name, no CA-issued certificate is realistic, and we
don't want to force the user through a commercial CA flow for a LAN app.

## Decision

Generate a self-signed X.509 certificate locally (`scripts/generate_certs.sh`)
and use it for the WSS server. Trust is established differently depending
on build mode:

- **Development mode:** the Android client accepts *any* certificate
  (`X509TrustManager` that trusts everything). This is explicitly labeled
  insecure and gated so it is never reachable in a release build.
- **Production mode:** the Android client pins the *exact* certificate by
  SHA-256 fingerprint, captured at pairing time from the `cert_fp` claim in
  the pairing JWT (see [ADR-002](./ADR-002-jwt-pairing.md)), and rejects
  any connection presenting a different certificate — this is TOFU
  (trust-on-first-use) via QR, not chain-of-trust via a CA.

## Rationale

- **A commercial CA can't issue a cert for a private LAN IP.** Certificate
  Authorities don't issue publicly-trusted certs for `192.168.x.x` or
  `.local` addresses without extra infrastructure (internal PKI, mDNS
  hostnames with a private CA, etc.) that's disproportionate for a
  personal two-device app.
- **Trust-all is fine for development, dangerous for release.** It lets
  developers iterate without fighting cert installation on every emulator
  wipe, but a device on the same Wi-Fi network could otherwise
  impersonate the Mac and intercept or forge call-control messages if this
  shipped to end users. See the LAN MITM entry in the threat model
  ([02_TDD.md §7](../02_TDD.md#7-threat-model)).
- **Fingerprint pinning solves it without a CA.** Because the phone learns
  the *exact* certificate fingerprint out-of-band (via the physically-
  proximate QR scan, already an implicit trust anchor per
  [ADR-002](./ADR-002-jwt-pairing.md)), it can validate the server's
  identity cryptographically on every connection without needing that
  cert to chase up to a root CA. An attacker who doesn't hold the Mac's
  private key cannot present a certificate with a matching fingerprint.
- **Fails closed.** If the Mac's certificate is ever regenerated (e.g.
  `generate_certs.sh` re-run), previously-paired phones' pinned
  fingerprint will no longer match, and the connection is refused rather
  than silently downgraded to trust-all. This is an intentional
  consequence, not a bug — see below.

## Consequences

- Regenerating certificates invalidates existing pairings; the user must
  re-scan a new QR on every paired phone. This is documented in
  [04_IMPLEMENTATION_GUIDE.md §13](../04_IMPLEMENTATION_GUIDE.md) as an
  expected operational step, not a support surprise.
- The macOS side still needs the certificate manually trusted in Keychain
  Access for the Flutter desktop WSS client (`badCertificateCallback` is
  likewise gated to development only via `kDebugMode` — see
  [02_TDD.md §6](../02_TDD.md#6-deployment-modes-development-vs-production)
  for the macOS-side production posture, which relies on the Keychain
  trust step rather than in-app pinning since `HttpClient` on macOS
  doesn't expose the same low-level pinning hook OkHttp does).
- `certs/device.der` (DER-encoded) must be generated alongside the PEM
  files because Android's `X509Certificate.getEncoded()` returns DER, and
  the fingerprint embedded in the QR must be computed over the same byte
  representation both sides use, or pinning will always fail. This is
  called out explicitly in
  [04_IMPLEMENTATION_GUIDE.md §3](../04_IMPLEMENTATION_GUIDE.md).

## Alternatives rejected

- **No TLS, plain WS** — rejected outright; call answer/reject control
  messages are too sensitive to send in cleartext on a shared network.
- **Ship a bundled root CA and have the app act as its own mini-CA** —
  solves the problem more "properly" but adds real key-management
  complexity (CA private key storage, revocation) for a two-node pairing
  that doesn't need it.
- **Always trust-all, even in production** — rejected; this is the
  specific gap flagged in review and closed by this ADR.
