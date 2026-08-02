# ADR-006: Flutter for the macOS desktop client

**Status:** Accepted
**Date:** 2026-08-03
**Related:** [01_SRS.md](../01_SRS.md)

## Context

The Mac side needs a small always-available UI: a QR pairing screen, an
incoming-call popup, and a contacts list for outgoing dial. The Android
side needs Dart for its UI layer regardless (contacts/pairing screens),
plus native Kotlin for telephony. Given Flutter is already required for
Android, does it also make sense for macOS, versus a native Swift/AppKit
app or an Electron app?

## Decision

Use Flutter's macOS desktop target (`flutter config --enable-macos-
desktop`) for the Mac client, sharing the `lib/` codebase (models, message
constants, theme, and most widgets) with the Android app.

## Rationale

- **Code sharing where it actually matters.** `CallManager`,
  `WebSocketService`, `CryptoService`, `Call`/message-type models, and the
  `CallPopup` widget are identical business logic regardless of platform.
  Writing this twice (once in Swift, once in Dart) doubles the surface
  area for the exact kind of state-ownership bugs ADR-003 exists to
  prevent.
- **Native Swift would still need a bridge for the phone-facing logic.**
  There's no phone-state logic on the Mac side to justify going native —
  the Mac app is a thin client (popup + contacts + QR), which plays to
  Flutter's strengths and avoids its weaknesses (no deep OS integration
  needed here beyond a WSS socket and a window).
- **Electron was rejected for footprint and consistency.** Pulling in a
  full Chromium runtime for a lightweight popup and contact list is heavy
  for what amounts to a small utility app, and would mean a *third* UI
  toolkit in the project (Dart on Android, Kotlin natively, JS/HTML on
  Mac) instead of one shared toolkit plus platform-specific native code
  only where the OS demands it (Android telephony).
- **`network_info_plus`, `qr_flutter`, `flutter_dotenv`** and the rest of
  the dependency set already need to work well on desktop for the QR
  screen; Flutter's desktop target has mature enough support for this
  narrow feature set (file I/O, basic networking, image rendering) that
  the risk is low.

## Consequences

- We are dependent on Flutter's macOS desktop support remaining solid for
  the specific plugins in use (`network_info_plus` for LAN IP,
  `qr_flutter` for QR rendering). If a plugin's desktop support lapses,
  that's a real risk unique to this decision — tracked as a maintenance
  item, not treated as a solved problem forever.
- The Mac app inherits Flutter's default look-and-feel unless deliberately
  themed (see `app_theme.dart`) — it will not automatically look like a
  "native" macOS app (no native menu bar integration, etc.). Acceptable
  for a Tier-1 utility popup; would need revisiting if this ever became a
  polished, App-Store-distributed product.
- Certificate trust on macOS goes through Keychain Access rather than an
  in-app pinning hook (see [ADR-004](./ADR-004-self-signed-tls.md)),
  because Dart's `HttpClient`/`IOWebSocketChannel` don't expose the same
  low-level `X509TrustManager` hook that OkHttp does on Android. This is
  a direct, acknowledged consequence of the toolkit choice.

## Alternatives rejected

- **Native Swift/AppKit Mac app** — cleanest platform integration, but
  duplicates all shared business logic in a second language and would
  need a bespoke bridge to keep the two clients' behavior in sync as the
  protocol evolves.
- **Electron** — rejected for bundle size and toolkit fragmentation, as
  above.
