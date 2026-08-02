# ADR-002: Use a self-issued JWT as the QR pairing payload

**Status:** Accepted
**Date:** 2026-08-03
**Related:** [03_API_PROTOCOL.md](../03_API_PROTOCOL.md), [04_TDD threat model](../02_TDD.md#7-threat-model)

## Context

Pairing needs to hand the phone three things in one QR scan: the Mac's LAN
IP, the WSS port, and (as of this revision) the server certificate's
SHA-256 fingerprint for pinning (see [ADR-004](./ADR-004-self-signed-tls.md)).
It also needs a way to say "this QR is stale, don't trust it" without a
second network round trip, since the phone hasn't connected to anything
yet at scan time — there's no server available to ask "is this code still
valid?".

Candidates considered:

1. Plain JSON blob in the QR, no signing or expiry
2. A random pairing code the phone sends to the server to exchange for
   connection details (requires a pre-existing channel — chicken/egg)
3. **JWT** (HS256) containing connection details plus `iat`/`exp`/`nbf`

## Decision

Encode the pairing payload as a compact HS256 JWT, signed with a secret
generated locally by `scripts/generate_secret.sh` and never transmitted
over the network. The Mac embeds the payload in the QR; the phone verifies
signature and expiry entirely offline before it ever opens a socket.

## Rationale

- **Self-contained expiry.** A JWT's `exp`/`nbf` claims let the *phone*
  reject a stale QR the instant it scans it — no server round trip needed,
  and no clock-trust issue beyond "the two devices' clocks are roughly
  in sync," which is a safe assumption on a home LAN.
- **Tamper-evidence for free.** Because the token is HMAC-signed with a
  secret that lives only in `.env` on the Mac, a phone that's never been
  paired can't be handed a forged QR by a third party unless that party
  also has the secret file — which is git-ignored and never leaves the
  Mac.
- **Off-the-shelf format.** JWT libraries and mental models are common
  enough that this isn't a bespoke crypto format someone has to relearn
  six months from now — it's a standard shape with well-understood failure
  modes (see the threat model in [02_TDD.md](../02_TDD.md)).
- **Extensible payload.** Adding `cert_fp` for certificate pinning (this
  revision) or a future `protocol_version` claim is a one-line change,
  not a schema migration.

## Consequences

- The JWT's `nonce` claim is currently generated but **not** tracked
  server-side, so it does not by itself prevent replay of a captured QR
  image within its validity window. This is called out explicitly as a
  residual risk in [02_TDD.md §7](../02_TDD.md#7-threat-model) rather than
  glossed over. The `exp` window (5 minutes) is the actual bound on replay
  risk today.
- HS256 means both devices effectively need to trust the same shared
  secret's confidentiality on the Mac's filesystem. This is acceptable for
  a personal LAN pairing flow but would not be appropriate if a third
  party ever needed to *issue* pairing tokens without holding Mac-side
  secrets (out of scope for Tier 1).
- We are not using JWT as a session/bearer token for ongoing
  authorization — it is single-use, scan-time-only. The WSS connection
  itself has no per-message auth after pairing; this is documented as an
  accepted Tier-1 LAN-trust boundary, not an oversight.

## Alternatives rejected

- **Plain unsigned JSON** — trivially forgeable by anything that can see
  or reconstruct the QR; no expiry semantics without inventing our own.
- **Server-issued short code exchanged post-connection** — solves replay
  and expiry more robustly (server can track single-use codes) but
  requires the phone to connect *before* it knows if the code is valid,
  which means the server must accept unauthenticated inbound connections
  first. JWT lets the phone fail closed before opening a socket at all.
