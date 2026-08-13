# Pakku Share Framework - STRIDE Threat Model

This document outlines the threat modeling for the Share Framework using the STRIDE methodology. 

## System Boundary
The system boundary includes the Android application, the macOS application, the WebSocket relay server (if applicable), and the local network. The primary assets are the user's clipboard data (which may contain highly sensitive information like passwords, tokens, or PII) and device resources.

---

## 1. Spoofing (Identity)
**Threat:** A malicious actor attempts to impersonate a paired device to send arbitrary clipboard content or images.
**Mitigation:** 
- The Share Framework operates strictly on top of the established `PlatformTransport` and `WebSocketService`. 
- Messages are only accepted over the authenticated, encrypted WebSocket connection established during the QR pairing phase.
- The framework implicitly trusts the transport layer; spoofing is mitigated at the authentication/transport layer, not the feature layer.

## 2. Tampering (Data Integrity)
**Threat:** A Man-In-The-Middle (MITM) or a malicious relay server modifies the payload in transit to alter clipboard content.
**Mitigation:**
- E2E encryption via the transport layer ensures data cannot be modified in transit.
- **EXIF Tampering/Exploits:** Images received are decoded into raw pixel buffers and re-encoded (stripping all metadata and EXIF) before being processed or placed on the clipboard. This neutralizing step prevents malicious EXIF payloads or image parser exploits from traversing the system.

## 3. Repudiation
**Threat:** A device sends a clipboard update but denies sending it.
**Mitigation:**
- This is a localized, single-user system across owned devices. Non-repudiation is strictly out-of-scope for the Share Framework as there is no multi-user auditing requirement.

## 4. Information Disclosure
**Threat:** Highly sensitive clipboard data (passwords, 2FA codes, personal photos) is leaked via logs, persistent storage, or third-party intercepts.
**Mitigation:**
- **No Payload Logging:** The framework strictly prohibits logging the contents of `body`, `imageBase64`, or clipboard text in any environment (Dart, Kotlin, Swift).
- **Ephemeral Storage:** Incoming and outgoing images are written to temporary cache files in an isolated app-private directory (`cacheDir/pakku_share/`). These files are actively deleted immediately after use (either after encoding outbound or after setting the clipboard inbound).
- **Memory Safety:** On macOS, the `decodedData` representing the image in memory is explicitly set to `nil` and released immediately upon popup dismissal or payload replacement.

## 5. Denial of Service (DoS)
**Threat:** An attacker or malfunctioning device sends massively oversized payloads or a flood of messages to crash the receiving app or exhaust memory.
**Mitigation:**
- **Size Limits:** Hard limits are enforced on both outbound and inbound paths.
  - Text is truncated to `64KB` (UTF-16 code units) prior to sending.
  - Images and Base64 payloads are strictly validated against a 5MB limit. Any payload exceeding this is silently dropped.
- **Binary Search Compression:** On outbound images, the Android service limits encoding iterations to a maximum of 7 to prevent CPU hangs during quality compression.
- **Deduplication:** A strict ID-based deduplication mechanism (`UUID-v4`) prevents infinite broadcast loops and redundant processing.
- **Failure Contract:** The framework uses a strict "Drop Silently" contract. Malformed payloads, unsupported MIME types, or decoding errors result in a silent drop. The framework will never crash, disconnect, or retry on invalid data.

## 6. Elevation of Privilege
**Threat:** A crafted payload causes the application to execute arbitrary code or perform actions outside its intended scope.
**Mitigation:**
- **Typed Dispatch:** The `ShareHandlerRegistry` uses strictly typed handlers. Payloads are routed based on `mime` type strings to specific, isolated handlers (`TextHandler`, `ImageHandler`).
- **No Eval/Dynamic Execution:** Payloads are purely treated as data (`String` or `Data/Uint8List`) and are never evaluated, executed, or deserialized into executable objects.
- **UI Thread Delegation:** All background heavy-lifting (decoding) is strictly sandboxed to background threads, and only safe, processed data is dispatched to the main UI thread to trigger standard platform APIs (`NSPasteboard` / `ClipboardManager`).
