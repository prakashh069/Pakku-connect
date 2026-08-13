# Connecto — Technical Design Document (TDD)

**Version:** 7.0
**Companion documents:** [01_SRS.md](./01_SRS.md) · [03_API_PROTOCOL.md](./03_API_PROTOCOL.md) · [04_IMPLEMENTATION_GUIDE.md](./04_IMPLEMENTATION_GUIDE.md) · [ADRs](./adr/)

---

## 1. Architecture Overview

```
                    ┌──────────────────────────┐
                    │   Android Phone           │
                    │                            │
                    │  ┌──────────────────────┐  │
                    │  │  PhoneStateService    │  │   <- single source of truth
                    │  │  (native, foreground) │  │      (ADR-003)
                    │  └──────────┬────────────┘  │
                    │             │ WSS (TLS, pinned in prod)
                    │  ┌──────────┴────────────┐  │
                    │  │  Flutter (pairing +    │  │
                    │  │  contacts UI only)     │  │
                    │  └───────────────────────┘  │
                    └─────────────┬──────────────┘
                                  │
                                  │  WSS
                                  ▼
                    ┌──────────────────────────┐
                    │  Node.js Relay (server.js)│   <- dumb forwarder
                    │  wss://<mac-ip>:8080      │      (ADR-005)
                    └─────────────┬──────────────┘
                                  │  WSS
                                  ▼
                    ┌──────────────────────────┐
                    │   macOS App (Flutter)     │      (ADR-006)
                    │                            │
                    │  QR pairing · Call popup   │
                    │  Contacts · Outgoing dial  │
                    └──────────────────────────┘
```

The Node relay and the Mac's Flutter process both run **on the Mac**, as
two separate OS processes — the relay is not embedded in the Flutter app
(see [ADR-005](./adr/ADR-005-node-vs-dart-server.md)).

## 2. Component Responsibilities

| Component | Owns | Never does |
|-----------|------|------------|
| `PhoneStateService` (Kotlin) | Reading real telephony state; executing native answer/reject/dial; missed-call notification | Any UI |
| Android Flutter layer | Pairing scan UI, contacts list, forwarding user taps to the relay as *requests* | Deciding call state on its own authority |
| Node relay (`server.js`) | Blind message forwarding between the two connected clients | Persisting messages, validating message shape, authenticating clients beyond TLS |
| Mac Flutter layer | QR generation, popup rendering, contacts, dial requests | Assuming a tap succeeded before `call_state` confirms it |

A Mac-side UI action (Accept/Decline) is allowed to update its **own**
local rendering optimistically for responsiveness (e.g. hide the
Accept/Decline buttons the instant the user taps one), but the popup is
only authoritatively dismissed by an incoming `call_state` message from
the phone, or a bounded client-side timeout as a fallback — never by the
tap alone. This nuance is intentional and is what keeps this design
consistent with [ADR-003](./adr/ADR-003-native-service-source-of-truth.md)
while still feeling responsive.

## 3. Sequence Diagrams

### 3.1 Pairing

```
Mac (Flutter)                                   Phone (Flutter)
     │                                                │
     │ 1. Read certs/device.der, compute SHA-256       │
     │    Build JWT { ws_ip, ws_port, cert_fp, exp }   │
     │ 2. Render QR                                    │
     │──────────────────────────────────────────────► │  (physical QR scan —
     │                                                  │   out-of-band channel)
     │                                                  │ 3. Verify JWT signature
     │                                                  │    + expiry, offline
     │                                                  │ 4. Store ws_ip/port/cert_fp
     │                                                  │ 5. Start PhoneStateService
     │                                                  │
     │ ◄──────────────── WSS connect (pinned cert) ────│ 6. Open WSS connection
     │                    via Node relay                │    through the relay
```

### 3.2 Incoming call — remote accept from the Mac

```
Phone Telephony      PhoneStateService        Node Relay        Mac (Flutter)
     │  RINGING              │                     │                  │
     ├───────────────────────►                     │                  │
     │                       │  incoming_call       │                  │
     │                       ├─────────────────────►├─────────────────►│
     │                       │                     │                  │  popup shown
     │                       │                     │      answer_call │◄─ user taps Accept
     │                       │◄─────────────────────┼──────────────────┤
     │                       │ acceptRingingCall()  │                  │
     │◄──────────────────────┤                       │                  │
     │  OFFHOOK               │                     │                  │
     ├───────────────────────►                     │                  │
     │                       │  call_state=answered │                  │
     │                       ├─────────────────────►├─────────────────►│
     │                       │                     │                  │  popup auto-dismisses
```

### 3.3 Incoming call — answered directly on the phone (auto-dismiss)

```
Phone Telephony      PhoneStateService        Node Relay        Mac (Flutter)
     │  RINGING              │                     │                  │
     ├───────────────────────►│  incoming_call      │                  │
     │                       ├─────────────────────►├─────────────────►│  popup shown
     │  user answers on the physical phone UI       │                  │
     │  OFFHOOK               │                     │                  │
     ├───────────────────────►│                     │                  │
     │                       │  call_state=answered │                  │
     │                       ├─────────────────────►├─────────────────►│  popup auto-dismisses
```

This is the flow that FR-7/SCOPE-7 exists for — the Mac never sent any
control message, yet its UI stays correct, because it only trusts
`call_state`, not its own assumptions.

### 3.4 Missed call

```
Phone Telephony      PhoneStateService
     │  RINGING              │
     ├───────────────────────►
     │  ... rings out ...     │
     │  IDLE (never OFFHOOK)  │
     ├───────────────────────►
     │                       │  showMissedCallNotification()
     │                       │  (local only — nothing sent to Mac)
```

### 3.5 Outgoing dial from the Mac

```
Mac (Flutter)          Node Relay        PhoneStateService       Telephony
     │  user taps a contact   │                  │                    │
     │  dial{number}          │                  │                    │
     ├────────────────────────►                  │                    │
     │                        ├─────────────────►│                    │
     │                        │                  │  ACTION_CALL intent │
     │                        │                  ├────────────────────►
```

### 3.6 Outgoing dial from the phone

```
Phone (Flutter)              MethodChannel            MainActivity (Kotlin)
     │  user taps a contact         │                          │
     │  invokeMethod('makeCall')     │                          │
     ├───────────────────────────────►                          │
     │                               ├─────────────────────────►│
     │                               │            ACTION_CALL intent
```

No relay round trip needed — dialing from the phone is entirely local.

## 4. Data Model

### 4.1 `Call` (Dart, shared)

```dart
enum CallDirection { incoming, outgoing }
enum CallState { ringing, answeredRemotely, declinedRemotely, ended }

class Call {
  final String phoneNumber;
  final String? contactName;
  final CallDirection direction;
  CallState state;
  final DateTime startedAt;
}
```

### 4.2 Pairing JWT payload

See [03_API_PROTOCOL.md](./03_API_PROTOCOL.md#2-pairing-jwt-payload) for
the full field-by-field contract.

## 5. Android API-Level Strategy

`PhoneStateListener` was deprecated in API 31 in favor of
`TelephonyCallback`. Both must be supported since `minSdkVersion` is 26:

| SDK range | Listener API used | Caller number availability |
|-----------|-------------------|------------------------------|
| 26–30 | `PhoneStateListener.onCallStateChanged(state, phoneNumber)` | Available if `READ_PHONE_STATE` **and** `READ_CALL_LOG` are both granted (API 29+ tightened this; below 29, `READ_PHONE_STATE` alone suffices). |
| 31+ | `TelephonyCallback` + `TelephonyCallback.CallStateListener.onCallStateChanged(state)` | **Not available from this callback at all** — Google removed the number parameter from the modern callback for privacy. See §5.1. |

The service version-gates registration at startup and funnels both paths
into one shared `handleStateChange(state, phoneNumber)` method so the
RINGING/OFFHOOK/IDLE/missed-call logic is written once — see
[04_IMPLEMENTATION_GUIDE.md §11.3](./04_IMPLEMENTATION_GUIDE.md).

### 5.1 Known limitation: caller ID on API 31+

On Android 12 and later, there is no supported way to get the ringing
caller's number from `TelephonyCallback` the way older `PhoneStateListener`
allowed. Getting it would require the app to register as a system
Dialer/`InCallService`, which is a materially larger scope increase (it
makes this app a candidate default phone app) and is **not** undertaken
in Tier 1. The accepted behavior: on API 31+, the popup shows "Unknown"
for the caller unless/until a future revision takes on `InCallService`
scope deliberately, with its own SRS update. This is documented here
precisely so nobody "fixes" it with a workaround that quietly expands
scope.

## 6. Deployment Modes: Development vs. Production

The original guide's `badCertificateCallback = (...) => true` (Mac/Dart)
and an all-trusting `X509TrustManager` (Android/Kotlin) are **acceptable
only in development** and must never ship as the production trust path.
See [ADR-004](./adr/ADR-004-self-signed-tls.md) for the full rationale.

| | Development | Production |
|---|---|---|
| **Android trust** | `X509TrustManager` that trusts any certificate; `hostnameVerifier` always returns true | Custom `X509TrustManager` that validates the presented cert's SHA-256 fingerprint against `cert_fp` captured from the pairing JWT; connection refused on mismatch |
| **macOS trust** | `badCertificateCallback` gated by `kDebugMode` returns `true` | Certificate manually trusted once in Keychain Access (System keychain, "Always Trust") — see [04_IMPLEMENTATION_GUIDE.md §13](./04_IMPLEMENTATION_GUIDE.md); the `kDebugMode` check ensures the trust-all callback cannot accidentally ship in a release build, enforcing Keychain trust as the only path in production. |
| **Gating** | Reachable only in debug builds (`BuildConfig.DEBUG` / Flutter's `kDebugMode`) | The only path reachable in a release build |
| **Failure mode on mismatch** | N/A — nothing is ever rejected | Connection is refused; user must re-pair (regenerate QR) |

Both code paths are shown explicitly, side by side, in
[04_IMPLEMENTATION_GUIDE.md §11.2](./04_IMPLEMENTATION_GUIDE.md) — the
guide never presents the trust-all path as if it were the shipping
implementation.

## 7. Threat Model

Since Connecto combines TLS, JWT pairing, QR distribution, and a
local network, each is examined for what it does and does not protect
against.

| Threat | Description | Mitigation | Residual risk |
|--------|--------------|------------|----------------|
| **Replay of a captured QR** | Someone photographs the QR during the 5-minute validity window and pairs before the intended device does. | `exp` claim bounds the window; `nonce` claim exists in the payload for future server-side single-use tracking. | **Not fully closed today** — the nonce is not yet tracked by any component, so anyone who captures the QR image within the validity window can pair. Documented in [ADR-002](./adr/ADR-002-jwt-pairing.md) as a known gap, not silently accepted. Mitigating factor: this requires simultaneous LAN presence and requires them to capture the *specific*, freshly-generated QR, which is only ever shown on request. |
| **Expired QR reuse** | Old QR code is scanned well after it was generated. | `exp`/`nbf` claims checked entirely offline by the phone before any connection attempt (FR-2). | Low — relies only on rough clock sync between devices, which is a safe LAN assumption. |
| **Stolen/leaked QR image** | The QR image itself is saved, screenshotted, or shared. | Same mitigation as replay, above — bounded by `exp`. The app never persists the QR image to disk or a shareable location. | Same as replay risk above, for the validity window. |
| **LAN MITM** | Another device on the same Wi-Fi network intercepts or spoofs traffic between phone and Mac. | Production mode's certificate fingerprint pinning (§6) means an attacker without the Mac's private key cannot present a certificate the phone will accept. | **Not mitigated at all in development mode** — trust-all accepts any certificate, including an attacker's. This must never leave development, which is why §6 exists as an explicit, hard mode boundary. |
| **Certificate replacement** | The Mac's certificate is regenerated (intentionally or by an attacker with filesystem access). | Pinning fails closed — connection refused rather than silently falling back to trust-all. | Requires the user to explicitly re-pair after any legitimate cert rotation — an operational cost, not a security gap. |
| **Device compromise** | Either the phone or the Mac's OS itself is compromised. | Out of scope — no app-level control can protect against a compromised OS. Mitigated only indirectly, by requesting the minimum permission set (NFR-7) so a compromised app component has the smallest possible blast radius. | Accepted; this is standard for any app-level threat model. |

**Overall posture:** this is a trust-on-first-use (TOFU) model anchored by
a physically-proximate QR scan, appropriate for a personal two-device LAN
pairing. It is explicitly **not** an enterprise PKI model, and should not
be marketed or assumed to be one.

## 8. Known Limitations Summary

- `TelecomManager.acceptRingingCall()` / `endCall()` do not work on every
  OEM Android skin. When unsupported, the user must act on the phone
  directly; the Mac popup still correctly auto-dismisses via `call_state`
  (§3.3), and the failure is surfaced via `lastNativeError`, never
  silent.
- Caller number is unavailable from the callback API on Android 12+
  (§5.1) — shown as "Unknown."
- QR replay within the validity window is not fully closed (§7).
