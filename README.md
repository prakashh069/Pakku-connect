# Pakku Connect — Documentation Set (v7.0)

A LAN call-control bridge between an Android phone and a Mac: pairing,
incoming-call popups, remote accept/decline, outgoing dial, contacts, and
native missed-call notifications. **No live call audio, ever** — see
[01_SRS.md](./01_SRS.md) §2.2.

## Reading order

| Doc | Answers |
|---|---|
| [01_SRS.md](./01_SRS.md) | What does this system do, and what does it explicitly *not* do? |
| [02_TDD.md](./02_TDD.md) | How is it built — architecture, sequence diagrams, dev/prod modes, threat model? |
| [03_API_PROTOCOL.md](./03_API_PROTOCOL.md) | What exactly goes over the wire? |
| [04_IMPLEMENTATION_GUIDE.md](./04_IMPLEMENTATION_GUIDE.md) | Step-by-step build, with full source. |
| [05_TEST_PLAN.md](./05_TEST_PLAN.md) | How do I know it actually works? |
| [adr/](./adr/) | Why each major technical decision was made, and what was rejected. |

## Architecture Decision Records

| ADR | Decision |
|---|---|
| [ADR-001](./adr/ADR-001-websocket-vs-grpc.md) | WebSocket over gRPC for signaling |
| [ADR-002](./adr/ADR-002-jwt-pairing.md) | JWT for the QR pairing handshake |
| [ADR-003](./adr/ADR-003-native-service-source-of-truth.md) | Native `PhoneStateService` as single source of truth |
| [ADR-004](./adr/ADR-004-self-signed-tls.md) | Self-signed TLS, dev trust-all vs. prod fingerprint pinning |
| [ADR-005](./adr/ADR-005-node-vs-dart-server.md) | Node.js relay instead of a Dart server |
| [ADR-006](./adr/ADR-006-flutter-for-desktop.md) | Flutter for the macOS desktop client |

## What changed in this revision

This revision folds in a full technical review:

- Split a single monolithic build guide into five purpose-specific docs
  plus a proper ADR set, so decisions don't get lost six months from now.
- Added sequence diagrams for pairing, incoming-call (both the
  Mac-initiated and phone-initiated-answer paths), missed calls, and both
  outgoing-dial directions.
- Centralized the wire protocol into one canonical table
  ([03_API_PROTOCOL.md](./03_API_PROTOCOL.md)) instead of leaving message
  shapes scattered across code samples.
- Added a threat model covering replay, expired/stolen QR codes, LAN
  MITM, certificate replacement, and device compromise.
- Replaced the single "accept every certificate" TLS client with an
  explicit, gated development-vs-production split — production now pins
  the server certificate by fingerprint instead of trusting anything
  presented to it.
- Added `TelephonyCallback` support for Android 12+ (API 31), alongside
  the legacy `PhoneStateListener` for older devices, instead of relying
  on a deprecated API that would generate build warnings on modern
  targets.
- Documented, rather than silently assumed, the real platform limitation
  that caller phone numbers are unavailable from the modern telephony
  callback on API 31+.
- Added `READ_CALL_LOG` permission handling with an honest, graceful
  fallback to "Unknown" caller display when it's unavailable or denied,
  instead of assuming the number would always be present.
