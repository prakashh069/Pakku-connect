# Phase 15.2a FileTransferService Cleanup Lifecycle Fix Report

## Root Cause Summary
`FileTransferService` was incorrectly destroying the WebSocket listener at the end of the *first* transfer within the `cleanupAndStop()` method. Because Android heavily reuses active service instances, if the user sent a second file back-to-back, or sent a batch of files causing multiple Intents, the reused `FileTransferService` was permanently deaf to macOS `ACK`/`READY` messages. This caused subsequent transfers to hang.

Additionally, the `cleanupAndStop()` method was called via a `finally` block using a default `success=false` parameter, creating misleading logs that implied failures even when transfers succeeded.

## Changes Implemented
1. **Transport Teardown Moved**: `transport.stopListening()` has been removed from `cleanupAndStop()`. It is now exclusively called in `override fun onDestroy()`. The transport listener survives as long as the OS keeps the service instance alive.
2. **Correct Transfer State Logging**: The `finally` block in `startTransfer` now captures the actual transfer result (`transferResultReported`) and passes it into `cleanupAndStop(isSuccess)`.

**New Logs Added:**
- `[FT_CLEANUP_START] success=<true/false>` (Replaces the old misleading `ENTERING CLEANUP` log)
- `[FT_SERVICE_STOP]` (Logged when `pendingTransfers <= 0` and `stopSelf()` is called)
- `[FT_SERVICE_DESTROYED]` (Logged inside `onDestroy()` right before listener teardown)

## Component Isolation
The fix strictly adheres to the boundaries. No modifications were made to:
- `MessageBus`
- `DeviceTransport`
- `NativePlatformBridge`
- `FileTransferManager`
- `FileReceiver`
- Chunk Protocol / ACK handling

The fix is ready for the sequential transfer and multi-image regression tests!
