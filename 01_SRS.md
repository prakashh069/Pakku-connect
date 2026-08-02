# Pakku Connect — Software Requirements Specification (SRS)

**Version:** 7.0
**Status:** Tier 1 — active build target
**Companion documents:** [02_TDD.md](./02_TDD.md) · [03_API_PROTOCOL.md](./03_API_PROTOCOL.md) · [04_IMPLEMENTATION_GUIDE.md](./04_IMPLEMENTATION_GUIDE.md) · [05_TEST_PLAN.md](./05_TEST_PLAN.md) · [ADRs](./adr/)

---

## 1. Purpose

Pakku Connect lets a user see and control their Android phone's call state
from their Mac while both devices are on the same local network: an
incoming-call popup on the Mac, remote accept/decline of that call, an
outgoing dial from either device's contacts, and a native missed-call
notification on the phone. It exists to remove the friction of reaching
for the phone every time it rings while working at a desk — nothing more.

## 2. Scope

### 2.1 In scope (Tier 1)

| ID | Capability |
|----|------------|
| SCOPE-1 | QR-code device pairing between one Mac and one Android phone |
| SCOPE-2 | Real-time signaling of incoming calls to the Mac |
| SCOPE-3 | Remote accept / decline of a ringing call, executed natively on the phone |
| SCOPE-4 | Outgoing call initiation from Mac contacts or phone contacts |
| SCOPE-5 | Native missed-call notification on the phone |
| SCOPE-6 | Contact search/list on both platforms |
| SCOPE-7 | Auto-dismissal of the Mac popup when the call state changes on the phone by any means (answered/declined directly on the phone) |

### 2.2 Explicitly out of scope

- **Live call audio in any form — this is a hard, standing prohibition,
  not a "later" item.** No component of this system may implement,
  route, transcode, or claim to support live voice audio between devices.
  Any future audio work is a separate "Tier 2" proposal requiring its own
  SRS and explicit sign-off; this document does not authorize it.
- Multi-device pairing (more than one phone per Mac, or vice versa)
- Call history sync
- SMS/messaging bridging
- Push notifications over the internet (WAN) — this is a LAN-only design
- Cross-platform desktop support beyond macOS (no Windows/Linux client)

## 3. Definitions

| Term | Meaning |
|------|---------|
| WSS | WebSocket Secure — the TLS-wrapped transport used for all signaling (see [ADR-001](./adr/ADR-001-websocket-vs-grpc.md)) |
| Relay | The Node.js process (`server.js`) that forwards messages between the paired Mac and phone (see [ADR-005](./adr/ADR-005-node-vs-dart-server.md)) |
| Pairing JWT | The signed token embedded in the QR code that carries connection details (see [ADR-002](./adr/ADR-002-jwt-pairing.md)) |
| Single source of truth | The rule that native Android telephony state, not Flutter state, is authoritative — see [ADR-003](./adr/ADR-003-native-service-source-of-truth.md) |
| Tier 1 | The complete, currently-authorized feature set defined in §2.1 |
| Tier 2 | Any future live-audio proposal — not authorized by this document |
| OEM restriction | A manufacturer-specific Android build that blocks or alters standard `TelecomManager` behavior |

## 4. Actors

- **User** — the person who owns both devices and pairs them once.
- **Mac app** — Flutter desktop client; shows QR, shows call popup, hosts
  contacts for outgoing dial.
- **Android app** — Flutter UI for pairing/contacts, plus the native
  `PhoneStateService` that is the actual authority on call state (see
  [ADR-003](./adr/ADR-003-native-service-source-of-truth.md)).
- **Relay server** — Node.js WSS process forwarding messages between
  exactly the two paired clients currently connected.

## 5. Functional Requirements

| ID | Requirement | Notes |
|----|-------------|-------|
| FR-1 | The Mac SHALL display a QR code encoding a signed, time-limited pairing token containing its LAN IP, WSS port, and certificate fingerprint. | See [ADR-002](./adr/ADR-002-jwt-pairing.md), [ADR-004](./adr/ADR-004-self-signed-tls.md). |
| FR-2 | The phone SHALL verify the pairing token's signature and expiry entirely offline before attempting any network connection. | Fails closed with a visible "Invalid or expired QR code" message. |
| FR-3 | On successful pairing, the phone SHALL start a foreground service (`PhoneStateService`) that persists across app restarts (`START_STICKY`). | |
| FR-4 | The phone SHALL detect a RINGING telephony state and send an `incoming_call` message to the Mac within the transport's normal LAN latency. | Target: popup visible on Mac within ~1.5 s on LAN — see NFR-1. |
| FR-5 | The Mac SHALL display a popup for a ringing call showing caller name (if resolvable) or number, with Accept and Decline actions. | If the number cannot be resolved (see known limitation in [04_IMPLEMENTATION_GUIDE.md](./04_IMPLEMENTATION_GUIDE.md) §11.3), the popup SHALL show "Unknown" rather than fail. |
| FR-6 | Tapping Accept/Decline on the Mac SHALL send `answer_call`/`reject_call` to the phone, which SHALL attempt the corresponding native `TelecomManager` action. | Where the native action is unsupported by the OEM, the phone/Mac SHALL surface a clear error — never fail silently (Agent Rule 7). |
| FR-7 | If the user answers or ends the call directly on the phone (bypassing the Mac), the phone SHALL send a `call_state` update and the Mac popup SHALL auto-dismiss. | This is the auto-dismiss requirement (SCOPE-7). |
| FR-8 | If a call rings and returns to idle without ever reaching OFFHOOK, the phone SHALL post a native, high-priority missed-call notification. | Local notification only — no cross-device signaling required for this one. |
| FR-9 | The user SHALL be able to initiate an outgoing call from a contact on either the Mac or the phone; the call SHALL always be placed by the phone's native dialer. | Mac-initiated dial routes through the relay as a `dial` message; phone-initiated dial is local. |
| FR-10 | Both apps SHALL provide a searchable contacts list (name and number). | |
| FR-11 | The relay SHALL forward messages between connected clients without persisting them beyond the forwarding operation. | See [ADR-005](./adr/ADR-005-node-vs-dart-server.md). |

## 6. Non-Functional Requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NFR-1 | Performance | Incoming-call popup SHALL appear on the Mac within ~1.5 s of RINGING on a typical home LAN. |
| NFR-2 | Security | All signaling traffic SHALL be encrypted in transit (TLS/WSS); production builds SHALL pin the server certificate rather than trust any presented certificate — see [ADR-004](./adr/ADR-004-self-signed-tls.md) and the threat model in [02_TDD.md §7](./02_TDD.md#7-threat-model). |
| NFR-3 | Reliability | The WSS client on both ends SHALL reconnect automatically with exponential backoff (capped) on disconnect. |
| NFR-4 | Reliability | The Android service SHALL restart automatically if killed by the OS (`START_STICKY`) and SHALL resume WSS connectivity without user intervention. |
| NFR-5 | Usability | Any native action failure (answer/reject/dial) SHALL produce a specific, human-readable message — never a silent no-op. |
| NFR-6 | Portability | Android `minSdkVersion` SHALL be 26; the app SHALL behave correctly (with documented degraded caller-ID behavior) up to the latest targeted SDK — see [02_TDD.md §6](./02_TDD.md#6-deployment-modes-development-vs-production) for the API-level handling strategy. |
| NFR-7 | Privacy | The app SHALL request the minimum telephony/contacts permissions required for each feature and SHALL degrade gracefully (not crash) when a permission is denied. |
| NFR-8 | Maintainability | No secrets, certificates, or keystores SHALL be committed to version control. |

## 7. Constraints and Assumptions

- Both devices are assumed to be on the same LAN/Wi-Fi segment; there is
  no WAN/relay-over-internet fallback in Tier 1.
- Exactly one phone and one Mac are paired at a time; concurrent multi-
  device pairing is not designed for and not tested.
- The user has physical access to both devices during pairing (the QR
  scan is the trust anchor — see [ADR-002](./adr/ADR-002-jwt-pairing.md)).
- Some `TelecomManager` behavior (native accept/reject) is OEM-dependent
  and may not work on all Android skins; this is a known, documented
  limitation, not a defect to "fix" by working around vendor restrictions.

## 8. Out-of-Scope Restatement

This SRS does not authorize, and no implementation derived from it should
attempt, any form of live call audio transport. If this requirement ever
changes, it requires a new SRS revision with its own threat model, not an
incremental addition to Tier 1.
