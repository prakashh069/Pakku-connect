# ADR-003: The native Android `PhoneStateService` is the single source of truth for call state

**Status:** Accepted
**Date:** 2026-08-03
**Related:** [02_TDD.md](../02_TDD.md), [03_API_PROTOCOL.md](../03_API_PROTOCOL.md)

## Context

Earlier iterations of this project bounced ownership of "what is the call
state right now" back and forth between Flutter (Dart) state and native
Android state, which produced race conditions: the Dart layer would think
a call was still ringing after the user had already answered it on the
phone's own dialer UI, because nothing told Flutter the state had changed
except a message *it* had sent.

## Decision

The Android `TelephonyManager`/`TelecomManager` state — read natively via
`PhoneStateService`, a foreground service — is the **only** authority for
"is there a call, and what state is it in." Every other component
(Flutter on the phone, the Node relay, Flutter on the Mac) is a passive
subscriber that reflects what the native service reports. Flutter never
guesses at call state from its own button presses; it waits for the
native layer's `call_state` message to confirm a transition.

## Rationale

- **The OS is the only component that can't be wrong about call state.**
  Telecom system events (RINGING, OFFHOOK, IDLE) are ground truth. Any
  state Flutter derives independently (e.g. optimistically marking a call
  "answered" the moment the Mac's Accept button is tapped) is a guess
  that can diverge from reality — for example if `acceptRingingCall()`
  silently fails on an OEM-restricted device (see
  [04_IMPLEMENTATION_GUIDE.md §11](../04_IMPLEMENTATION_GUIDE.md), known
  limitation).
  - **Note:** the current `CallManager.answerCall()`/`rejectCall()`
    implementation on the Mac side does still optimistically transition
    local UI state immediately on tap, for responsiveness, but the popup
    is authoritatively cleared only by the subsequent `call_state`
    message from the phone (or a timeout fallback). This is intentional:
    it's a UI responsiveness affordance layered *on top of* the
    single-source-of-truth rule, not a violation of it — see
    [02_TDD.md §2](../02_TDD.md#2-component-responsibilities) for the
    exact contract.
- **Debuggability.** When something is wrong, "check what
  `PhoneStateService` last logged" is always the right first step, instead
  of having to reconcile three different components' independent
  understanding of state.
- **Symmetry with the missed-call feature.** Missed-call detection
  (RINGING → IDLE with no OFFHOOK in between) can only be observed
  natively; putting it in the same service that owns all other state
  transitions avoids a second, parallel state machine.

## Consequences

- All UI-triggered actions (Accept/Decline/Dial from the Mac) are framed
  as **requests**, not state changes — the Mac popup shows "call answered
  on phone" language rather than assuming success, and displays
  `lastNativeError` when the native action is known to have failed. See
  Agent Rule 7: "When native answer/reject is unsupported, show a clear
  user message — never fail silently."
- The Flutter layer on Android is intentionally "dumb" for call handling:
  it does pairing UI and contacts, and otherwise gets out of the way.
- This constrains us to a foreground service with `phoneCall` type, which
  has stricter lifecycle rules (Android 12+) that must be respected —
  see the API-level notes in [02_TDD.md](../02_TDD.md).

## Alternatives rejected

- **Flutter owns state, native is a dumb executor** — this was the
  earlier, rejected design. It produced exactly the drift bugs described
  above.
- **Split ownership (Flutter owns "user intent," native owns "OS
  fact")** — sounds appealing but in practice means every consumer has to
  know which of two conflicting signals to trust, which is strictly worse
  than one clear owner.
