# ADR-001: Use WebSocket (WSS) for signaling instead of gRPC

**Status:** Accepted
**Date:** 2026-08-03
**Related:** [03_API_PROTOCOL.md](../03_API_PROTOCOL.md), [ADR-005](./ADR-005-node-vs-dart-server.md)

## Context

Connecto needs a bidirectional, low-latency channel between exactly two
LAN peers (an Android phone and a Mac) to relay small, infrequent signaling
events: `incoming_call`, `call_state`, `answer_call`, `reject_call`, `dial`.
No audio or video media ever crosses this channel (explicitly forbidden —
see [01_SRS.md](../01_SRS.md) §2, out of scope). We need to pick a transport.

Candidates considered:

1. **gRPC** (bidirectional streaming) over HTTP/2
2. **WebSocket** over TLS (WSS)
3. **Raw TCP socket** with a custom framing protocol
4. **MQTT** via a local broker

## Decision

Use a single WebSocket connection per pairing, secured with TLS (WSS),
carrying newline-free JSON text frames.

## Rationale

- **Payload size and shape don't justify gRPC.** Every message in the
  protocol is a handful of string/number fields (see
  [03_API_PROTOCOL.md](../03_API_PROTOCOL.md)). Protobuf's compactness and
  schema evolution guarantees solve a problem we don't have at this scale.
- **Tooling symmetry.** `web_socket_channel` (Dart) and `OkHttp`'s
  `WebSocket` (Kotlin) are both first-class, well-maintained libraries with
  minimal boilerplate. A gRPC client on Flutter desktop (macOS) is
  meaningfully harder to wire up than gRPC on mobile-only targets, and the
  Mac side is a hard requirement here.
- **No code generation step.** gRPC requires a `.proto` file, a build step,
  and generated stubs on both Dart and Kotlin sides. For a two-person,
  six-message protocol, this is process overhead that actively works
  against "keep `.env`, certs, and keystores out of git" simplicity goals.
- **Debuggability.** JSON-over-WebSocket is trivially inspectable with
  `wscat`, browser devtools, or a log line. Protobuf frames require the
  schema to decode, which slows down field debugging on a consumer LAN app.
- **Full duplex is native to WebSocket**, which is exactly the shape we
  need (Mac → Phone control messages, Phone → Mac state messages, on the
  same socket, no polling).

## Consequences

- We give up gRPC's built-in schema versioning and code-generated type
  safety. Mitigated by centralizing the wire contract in
  [03_API_PROTOCOL.md](../03_API_PROTOCOL.md) and adding a `v` field
  recommendation for forward compatibility (see that doc's versioning
  note).
- We give up gRPC's built-in flow control and multiplexing. Not needed —
  this is a single low-frequency stream, not a data-heavy pipe.
- If Connecto ever needs multiple concurrent typed RPC-style calls
  (e.g. a future "sync call history" bulk endpoint), gRPC should be
  revisited at that time rather than retrofitted now.

## Alternatives rejected

- **Raw TCP + custom framing** — reinvents ping/pong, reconnect, and TLS
  wrapping that WebSocket already gives us for free.
- **MQTT** — assumes a broker process, which adds a moving part (broker
  lifecycle, topic ACLs) for a two-device pairing that doesn't need
  publish/subscribe fan-out.
