# Pakku Connect — Test Plan

**Version:** 7.0
**Companion documents:** [01_SRS.md](./01_SRS.md) · [02_TDD.md](./02_TDD.md) · [03_API_PROTOCOL.md](./03_API_PROTOCOL.md) · [04_IMPLEMENTATION_GUIDE.md](./04_IMPLEMENTATION_GUIDE.md)

This document is run end-to-end before calling any build "done." It is
kept separate from the implementation guide so it can be re-run against a
built app without touching build instructions, and so CI/manual-QA
ownership is obvious.

---

## 1. Unit Tests

```bash
flutter test
```

Covers `test/core/crypto_service_test.dart` (§14 of
[04_IMPLEMENTATION_GUIDE.md](./04_IMPLEMENTATION_GUIDE.md)): JWT
round-trip (with and without `cert_fp`), expiry rejection, tamper
rejection, and missing-secret failure.

**Pass criterion:** all cases green, zero skipped.

## 2. Manual Verification Checklist

Run in order — later steps assume earlier ones passed.

### 2.1 Setup

1. `./scripts/generate_secret.sh && ./scripts/generate_certs.sh`
2. `node server.js` — confirm "WSS server listening on port 8080".
3. Trust the certificate on the Mac via Keychain Access (§13.1 of the
   implementation guide). **Do not** manually install the cert on
   Android — production pairing should not require it (§13.2).

### 2.2 Pairing

4. Run the Mac app → QR appears within a couple seconds, no error text
   under it (an error here means `certs/device.der` wasn't generated —
   re-check step 1).
5. Run the Android app → scan the QR → pairing succeeds → phone/contacts/
   notification permission prompts appear → native service starts.
6. Confirm (via `adb logcat -s PhoneStateService`) the WSS connection
   opens using the **production pinned client**, not the dev trust-all
   fallback — the log line differs between the two paths (§11.3 of the
   implementation guide).

### 2.3 Core call flow

7. Place a real incoming call to the paired phone → popup appears on the
   Mac within ~1.5 s (NFR-1).
8. Tap **Accept** on the Mac → phone executes the native answer action;
   confirm the call is actually connected on the phone.
9. Repeat with **Decline** → phone executes the native reject action;
   call ends.
10. **Answer the call directly on the phone** (bypass the Mac) → Mac
    popup auto-dismisses without the Mac ever sending a control message
    (FR-7 / SCOPE-7).
11. Reject/end the call directly on the phone → Mac popup auto-dismisses.

### 2.4 Missed calls

12. **Let a call ring out without answering** → a native, high-priority
    missed-call notification appears on the phone (FR-8).

### 2.5 Outgoing dial

13. Open Contacts on the Mac → tap a contact → phone places the call
    (FR-9, §3.5 sequence in [02_TDD.md](./02_TDD.md)).
14. Open Contacts on the phone → tap a contact → phone places the call
    directly, no relay round trip (§3.6 sequence).

### 2.6 Resilience

15. Kill and reopen the Android app → the foreground service persists or
    restarts (`START_STICKY`) and WSS connectivity resumes without user
    action (NFR-4).
16. Turn off Wi-Fi on the phone briefly, then back on → the WSS client
    reconnects with backoff on both ends (NFR-3) without requiring an
    app restart.

### 2.7 Security-path checks (new in this revision)

17. On an API 31+ device, confirm the popup shows caller number as
    "Unknown" — this is expected per §5.1 of
    [02_TDD.md](./02_TDD.md), not a defect.
18. Deliberately corrupt `cert_fp` in `pakku_prefs.xml` on the phone
    (see §11.3 verification in the implementation guide) → the service
    logs a `CertificateException` and does **not** connect. Restore the
    correct value (or re-pair) to recover.
19. Re-run `generate_certs.sh` on the Mac → an already-paired phone fails
    to reconnect until it re-scans a fresh QR (§13.2). Confirm this is a
    clean refusal, not a silent downgrade to an insecure connection.
20. Deny the `READ_CALL_LOG` prompt during pairing on an API ≤ 30 device
    → incoming calls still work end-to-end, with the caller shown as
    "Unknown" instead of the app crashing or blocking pairing.
21. Deny `CALL_PHONE` and attempt an outgoing dial from the phone's
    contacts → `CallManager.dial` surfaces `lastNativeError` ("Unable to
    place call") in the popup rather than failing silently (Agent Rule
    7).

### 2.8 Build hygiene

22. `flutter test` passes (§1).
23. `git status` after a full build shows `.env`, `certs/*`, and any
    keystore untracked.
24. A release build (not debug) with no `cert_fp` present refuses to
    connect rather than falling back to trust-all — confirm via logcat
    (§11.3 verification in the implementation guide). This is the single
    most important negative test in this plan: it's the difference
    between "insecure by an explicit, gated exception" and "insecure by
    default."

## 3. Definition of Done (Tier 1)

- [ ] QR pairing establishes a live, certificate-pinned WSS connection in
      production mode.
- [ ] Incoming call produces a popup on the Mac within ~1.5 s on LAN.
- [ ] Accept / Decline signals are executed by the phone's native
      service, with failures surfaced via `lastNativeError` rather than
      silently ignored.
- [ ] The Mac popup auto-dismisses correctly regardless of which device
      the user actually answers/ends the call from.
- [ ] Missed calls produce a local high-priority notification on the
      phone.
- [ ] Outgoing dial works from both Mac and phone.
- [ ] The native `PhoneStateService` is confirmed as the single source of
      truth — no test in §2.3 depends on Flutter-side state guessing.
- [ ] API 31+ devices are handled via `TelephonyCallback`, not a
      deprecated `PhoneStateListener` call that happens to still compile.
- [ ] Production builds never reach the trust-all TLS path (§2.8, item
      24).
- [ ] Clear limitation messaging exists for OEM-restricted devices and
      for API 31+ caller-ID unavailability.
- [ ] No secrets, certs, or keystores committed.
- [ ] No unused dependencies (`flutter_local_notifications` remains
      removed — see §4 of the implementation guide).
- [ ] UI copy never claims live audio, anywhere in either app.
- [ ] Unit tests pass.

**If any box is unchecked, this is not a Tier-1-complete build. Do not
begin Tier 2 (live audio) work — it is not authorized by
[01_SRS.md](./01_SRS.md) regardless of how complete Tier 1 is.**
