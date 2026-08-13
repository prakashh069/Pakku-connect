# Connecto — API / Protocol Specification

**Version:** 7.0 (protocol implicitly v1 — see §4 versioning note)
**Transport:** WSS (WebSocket over TLS), one JSON object per text frame
**Companion documents:** [02_TDD.md](./02_TDD.md) · [ADR-001](./adr/ADR-001-websocket-vs-grpc.md) · [ADR-002](./adr/ADR-002-jwt-pairing.md)

This is the single canonical source for every message Connecto sends
over the wire. If code and this document ever disagree, this document is
correct and the code has a bug — update code to match, not the reverse,
unless the change is deliberate and this doc is updated in the same
change.

---

## 1. Message Contract

All messages are flat JSON objects with a required `type` field. The relay
forwards every message verbatim to all *other* connected clients — it does
not validate shape (see [ADR-005](./adr/ADR-005-node-vs-dart-server.md)),
so both endpoints must defensively handle malformed input (already true of
`WebSocketService._onMessage`, which swallows parse errors).

| Message `type` | Sender | Receiver | Required fields | Optional fields | Triggers | Notes |
|---|---|---|---|---|---|---|
| `incoming_call` | Phone | Mac | `phoneNumber: string` | `contactName: string` | Mac shows the call popup (FR-5) | `phoneNumber` is `"Unknown"` when the OS doesn't expose it — see [02_TDD.md §5.1](./02_TDD.md#51-known-limitation-caller-id-on-api-31) |
| `call_state` | Phone | Mac | `state: "answered" \| "ended"` | — | Mac auto-dismisses or updates the popup (FR-7) | This is the **only** authoritative call-state signal — see [ADR-003](./adr/ADR-003-native-service-source-of-truth.md) |
| `answer_call` | Mac | Phone | — | — | Phone attempts `TelecomManager.acceptRingingCall()`; on success the phone will subsequently emit `call_state=answered` once OFFHOOK is observed | Does **not** itself confirm success — the Mac must wait for `call_state`, or for `lastNativeError` on native failure |
| `reject_call` | Mac | Phone | — | — | Phone attempts `TelecomManager.endCall()` (API 29+) or `silenceRinger()` (below); phone will subsequently emit `call_state=ended` | Same caveat as `answer_call` |
| `dial` | Mac | Phone | `number: string` | — | Phone launches `Intent.ACTION_CALL` for `number` | Requires `CALL_PHONE` permission on the phone; on failure the phone should log and the Mac has no automatic feedback path today (see §5 open item) |
| `error` | Relay | Either client | `payload: string` | — | Client should log/display; not a fatal condition by itself | Currently only emitted by the relay on invalid JSON — see `server.js` |

### 1.1 Message field types (strict)

```typescript
// incoming_call
{ type: "incoming_call", phoneNumber: string, contactName?: string }

// call_state
{ type: "call_state", state: "answered" | "ended" }

// answer_call / reject_call
{ type: "answer_call" } | { type: "reject_call" }

// dial
{ type: "dial", number: string }

// error
{ type: "error", payload: string }
```

## 2. Pairing JWT Payload

Carried inside the QR code (see [ADR-002](./adr/ADR-002-jwt-pairing.md)),
signed HS256 with the secret in `.env`. Never transmitted over the WSS
channel — it is consumed entirely at scan time, offline.

| Claim | Type | Required | Meaning |
|---|---|---|---|
| `iss` | string | yes | Always `"connecto"` |
| `sub` | string | yes | The issuing device's `device_id` |
| `aud` | string | yes | Always `"connecto_client"` |
| `iat` | number (unix seconds) | yes | Issued-at time |
| `exp` | number (unix seconds) | yes | Expiry — default 5 minutes after `iat` |
| `nbf` | number (unix seconds) | yes | Not-before — equal to `iat` |
| `device_id` | string | yes | Stable identifier for the issuing (Mac) device |
| `device_name` | string | yes | Human-readable hostname, shown nowhere critical |
| `platform` | string | yes | `"macOS"` in current usage |
| `nonce` | string | yes | Random per-token value; **not currently tracked server-side** — see the replay entry in [02_TDD.md §7](./02_TDD.md#7-threat-model) |
| `ws_ip` | string | yes for pairing to succeed | LAN IP of the WSS server |
| `ws_port` | number | yes for pairing to succeed | WSS server port |
| `cert_fp` | string (lowercase hex SHA-256) | yes in production mode | Fingerprint of `certs/device.der`, used for certificate pinning — see [ADR-004](./adr/ADR-004-self-signed-tls.md) |

## 3. Error Handling Contract

- Any WSS frame that fails `jsonDecode`/`JSONObject` parsing is dropped
  silently by the **receiving** client (both `WebSocketService._onMessage`
  in Dart and the `onMessage` handler in `PhoneStateService.kt` wrap
  parsing in a try/catch and log rather than crash).
- The **relay** additionally replies to the *sending* client with an
  `error` message when it cannot parse the incoming frame as JSON at all
  (see `server.js`). This is the one case where `error` is actually
  emitted today.
- A message with an unrecognized `type` is ignored by both clients (no
  `error` is generated for this case currently — treated as safe
  forward-compatibility rather than a fault, per §4 below).

## 4. Versioning Note

The protocol has no explicit version field today; every client assumes it
is talking to another client running the exact same message set. This is
acceptable while there is exactly one shipping version of each client, but
is flagged here for anyone extending the protocol:

- **Recommendation for the next protocol change:** add an optional `v:
  number` field to every message (defaulting to `1` when absent for
  backward compatibility), and have each client ignore any message whose
  `v` it doesn't understand rather than attempting to parse unfamiliar
  fields. This keeps the "unrecognized type is ignored, not fatal" posture
  in §3 consistent as the protocol grows, instead of introducing a
  breaking change silently.
- Do not repurpose an existing `type` string for a different payload shape
  — always introduce a new `type` value instead, so this table stays a
  reliable single source of truth.

## 5. Open Items

- `dial` has no success/failure acknowledgment path back to the Mac
  today — if the phone can't place the call (e.g. `CALL_PHONE` denied),
  the Mac currently has no way to know. The protocol is intentionally left
  unchanged for now. Acknowledgement messages will not be added unless
  implementation demonstrates they are strictly required, at which point a
  protocol revision would be proposed.
