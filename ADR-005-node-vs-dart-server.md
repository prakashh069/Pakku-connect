# ADR-005: Node.js WSS relay instead of a Dart server

**Status:** Accepted
**Date:** 2026-08-03
**Related:** [ADR-001](./ADR-001-websocket-vs-grpc.md), [04_IMPLEMENTATION_GUIDE.md §12](../04_IMPLEMENTATION_GUIDE.md)

## Context

Something has to run the WSS endpoint that both the phone and the Mac
connect to. The Mac app is already Flutter/Dart. It's fair to ask: why not
run the relay as a Dart process (`dart:io`'s `HttpServer` +
`package:web_socket_channel`) instead of introducing a second runtime
(Node.js) into the project?

## Decision

Run the relay as a small standalone Node.js process (`server.js`, using
`ws`), separate from the Flutter Mac app.

## Rationale

- **The relay's job is trivial and stateless**: accept two WSS
  connections, forward any message from one to the other, verbatim. `ws`
  is a minimal, extremely well-trodden library for exactly this, with a
  tiny dependency surface (`ws`, `dotenv`).
- **Process isolation from the UI.** Keeping the relay as its own process
  means it can be restarted, logged, and reasoned about independently of
  the Mac's Flutter UI process. If the Flutter app crashes or is mid-
  rebuild during development (`flutter run` hot restarts), the relay
  doesn't need to go down with it.
- **Lower ceremony for a pure network relay.** Dart's `HttpServer` +
  manual WebSocket upgrade handling for a bare relay is more boilerplate
  than `require('ws')`; Node's HTTPS + `ws` combination is closer to a
  10-line server for this exact shape of problem.
- **Operational familiarity.** A relay this small is easy to run under any
  standard process supervisor (`launchd`, `pm2`, a plain background
  shell) — none of which care what runtime it's in, so we optimized for
  "least code to write and audit," not for stack uniformity.

## Consequences

- The project now has two runtimes to install and keep updated (Flutter/
  Dart for the apps, Node.js for the relay), which is a real cost for a
  contributor bootstrapping the repo. This is mitigated by keeping
  `server.js` deliberately tiny (see
  [04_IMPLEMENTATION_GUIDE.md §12](../04_IMPLEMENTATION_GUIDE.md)) so
  there's very little Node-specific code to actually maintain.
  `npm install` is the only extra bootstrap step.
- If the relay ever needs to do more than blind-forward (e.g. validate
  message shape server-side, enforce that only two clients may be
  connected at once, rate-limit), that logic will live in JavaScript, not
  Dart — a contributor working on relay logic needs baseline Node
  familiarity.
- Because the relay is intentionally dumb (broadcasts to all other
  connected clients, does no auth), it inherits the LAN-trust assumptions
  documented in the threat model
  ([02_TDD.md §7](../02_TDD.md#7-threat-model)) — this would need to
  change before the relay could ever be exposed beyond a local network,
  regardless of which runtime it's written in.

## Alternatives rejected

- **Dart server (`dart:io` + `web_socket_channel` server mode)** — would
  unify the stack to one language, and remains a reasonable future
  migration if the relay ever needs to share code (models, message
  constants) with the Flutter apps. Rejected for now because the relay is
  too small for stack unification to pay for the extra server-side Dart
  boilerplate today; revisit if the protocol grows.
- **Embedding the relay inside the Mac Flutter app itself (no separate
  process)** — rejected because it couples the phone's ability to talk to
  the Mac to the Mac's Flutter UI process being alive and responsive,
  which is a worse failure mode than a small independent relay.
