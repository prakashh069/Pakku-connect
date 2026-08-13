# Pakku Share Framework - Manual QA Test Plan

This document outlines the manual verification scenarios for the Pakku Share Framework (currently supporting Clipboard text and images).

## 1. Test Environments
Ensure you have the following environments configured for paired testing:
- **Device A:** Android (Sender / Receiver)
- **Device B:** macOS (Receiver)
*(Note: Ensure devices are successfully paired and connected over the same local network or WebSocket relay before proceeding).*

## 2. Functional Scenarios (Golden Path)

### 2.1 Text Sharing (Android -> macOS)
1. **Short Text:** Copy a short string ("Hello World") on Android.
   - **Expected:** macOS displays a non-intrusive popup showing the text. The text is available in `NSPasteboard` for pasting.
2. **Long Text:** Copy a very large block of text (e.g., several paragraphs, < 64KB).
   - **Expected:** macOS displays the popup with truncated preview text, but the full text is copied to the clipboard.
3. **Special Characters & Emojis:** Copy text containing emojis and Unicode characters (e.g., "Hello 🌍! おはよう").
   - **Expected:** The text transfers flawlessly without encoding corruption.

### 2.2 Image Sharing (Android -> macOS)
1. **Standard Image:** Share a small PNG or JPEG image from Android via the system Share menu to Pakku.
   - **Expected:** Android shows a success toast. macOS displays a popup with the image preview. The image is available in the clipboard.
2. **Large Image (Binary Search Compression):** Share a high-resolution, multi-megabyte photo from the Android gallery.
   - **Expected:** Android performs background binary search compression. It should successfully send within a few seconds (as long as it can be compressed under 5MB encoded). macOS receives and displays the image.

### 2.3 Android Receive Path (macOS -> Android)
*(If macOS sending is implemented or mock-sent for testing)*
1. **Foreground Receive:** While the Pakku Android app is open, receive a share.
   - **Expected:** A Toast appears, and the item is directly copied to the Android clipboard.
2. **Background Receive (Draw Overlays Granted):** App is in the background, "Display over other apps" permission is granted.
   - **Expected:** A transparent popup/activity executes the copy seamlessly and disappears, showing a Toast.
3. **Background Receive (No Overlay Permission):** App in background, permission denied.
   - **Expected:** A high-priority Heads-Up Notification appears. Tapping the "Copy" action executes the copy.

## 3. Edge Cases & Resilience

### 3.1 Oversized Payloads
1. **Oversized Text (> 64KB):** Copy a 100KB text string on Android.
   - **Expected:** Android gracefully truncates the payload to 64KB (UTF-16 code units) before sending. macOS receives the truncated text successfully.
2. **Oversized Image (Uncompressable > 5MB):** Share an extremely large image (e.g., a massive 50MB TIFF/PNG) that cannot be compressed to under 5MB Base64.
   - **Expected:** Android logs a warning and drops the payload. A toast is shown: "Image too large to send". The WebSocket connection remains perfectly stable.

### 3.2 Protocol Failure Contract
*These require intercepting/mocking WebSocket traffic.*
1. **Malformed JSON:** Send a corrupted JSON payload to the receiver.
   - **Expected:** Silent drop. No crashes.
2. **Unsupported MIME Type:** Send a payload with `mime: "application/pdf"`.
   - **Expected:** The `ShareHandlerRegistry` logs and silently drops the message.
3. **Unsupported Schema Version:** Send a payload with `schemaVersion: 2` or `schemaVersion: 0`.
   - **Expected:** Silent drop.
4. **Missing ID:** Send a valid payload missing the `id` field.
   - **Expected:** Silent drop.

## 4. Concurrency & UI Stress
1. **Rapid Replacements:** Copy 5 different text strings on Android in rapid succession (e.g., 1 per second).
   - **Expected:** macOS processes them sequentially. The macOS popup updates its content dynamically without dismissing and recreating a new window. Only the last copied string remains in the clipboard.
2. **Rapid Image Sharing:** Share 3 images rapidly from Android.
   - **Expected:** macOS handles the background decoding safely. Stale decodes are discarded if a newer image arrives before the decode completes.
3. **Clicking Copy button mid-decode:** Click the copy button on the macOS popup while the image is still being decoded.
   - **Expected:** App does not crash; handles state gracefully.

## 5. Security & Resource Cleanup
1. **Cache Cleanup (Android):** Share an image from Android. Verify that the temporary file in `cacheDir/pakku_share/` is deleted immediately after encoding.
2. **Cache Cleanup (Android Receive):** Receive an image on Android. Verify the temporary file is deleted after the clipboard is populated.
3. **Memory Cleanup (macOS):** Monitor macOS memory usage while rapidly sharing images.
   - **Expected:** Memory usage remains stable. `decodedData` is successfully freed on popup dismissal or payload replacement.
4. **No EXIF Data:** Share an image containing GPS coordinates from Android. Paste it on macOS and inspect it.
   - **Expected:** All EXIF data (GPS, camera model, orientation) is completely stripped.
