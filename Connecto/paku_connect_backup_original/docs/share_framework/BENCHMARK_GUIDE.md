# Pakku Share Framework: Benchmark Guide

This guide details how to execute the performance benchmarks for the Share Framework's image processing pipeline. The benchmarks are divided into Android (sender) and macOS (receiver) test harnesses.

## Measured Metrics

The benchmarks simulate the most intensive part of the share framework (Image sharing) and measure:
- **Android:** Image Decode, Lossless PNG Encoding, JPEG Binary Search Compression (Quality 30-100, target <= 5MB), Base64 Encoding, and Peak Memory Footprint.
- **macOS:** Base64 Decoding, NSImage Creation (Popup latency), NSPasteboard Write (Clipboard write latency), and Memory Delta.

---

## 1. Running Android Benchmarks

The Android benchmark is written in Kotlin and isolates the exact encoding and compression logic used in `PhoneStateService.kt`.

**Location:** `benchmarks/android/ShareBenchmarkTest.kt`

### How to Run

1. Open the project in Android Studio or use a local scratch environment.
2. Ensure you have a sample high-resolution image file (e.g., a 10MB JPEG or PNG photo).
3. From any test target or debug Activity, invoke the benchmark runner:

```kotlin
import com.pakku.pakku_connect.benchmark.ShareBenchmarkTest
import java.io.File

// Provide a path to a real image file on the device
val testFile = File("/sdcard/Download/test_image.jpg")
ShareBenchmarkTest().runBenchmarks(testFile)
```

### Expected Output Format
```text
=== Pakku Share Framework: Android Benchmarks ===
Target File: test_image.jpg (8192 KB)
[Memory] Bitmap Memory Footprint: 32 MB
[Decode] BitmapFactory.decodeFile: 45ms
[Encode] PNG Compress (100%): 310ms -> 12450 KB
[Compress] JPEG Binary Search (4 iterations): 140ms -> 3900 KB (Quality: 82)
[Encode] Base64 Encoding: 20ms -> 5100 KB payload
[Memory] Peak Pipeline Delta: 45 MB
=================================================
```

---

## 2. Running macOS Benchmarks

The macOS benchmark isolates the Base64 extraction, image decoding, and clipboard mutation logic from `ClipboardPanelController.swift`.

**Location:** `benchmarks/macos/ShareBenchmarkTests.swift`

### How to Run

1. Open `macos/Runner.xcworkspace` in Xcode.
2. From anywhere in your Swift code (e.g., `AppDelegate.swift` during debug initialization), invoke the static runner with a heavy Base64 payload.

```swift
// Generate or provide a massive Base64 string for testing
let hugeBase64 = String(repeating: "A", count: 5 * 1024 * 1024) // 5MB string
ShareBenchmarkTests.runBenchmarks(base64Payload: hugeBase64)
```

### Expected Output Format
```text
=== Pakku Share Framework: macOS Benchmarks ===
Payload Size: 5120 KB
[Decode] Base64 -> Data: 12.40ms
[Decode] Data -> NSImage: 8.15ms
[Memory] Decode Delta: 15.20 MB
[Write] NSPasteboard setData: 4.30ms
[Memory] Final Delta (before GC): 15.20 MB
===============================================
```

---

## Performance Thresholds (Success Criteria)

When running these benchmarks on physical devices, the Share Framework is considered performant if it meets the following criteria:

- **Android Compression (JPEG Binary Search):** Should complete within **< 500ms** on modern hardware (Snapdragon 8 Gen 1+ / Tensor G2).
- **Android Base64 Encoding:** Should complete in **< 50ms** for a 5MB payload.
- **macOS Base64 Decoding:** Should complete in **< 20ms**.
- **macOS Popup Latency (Data to NSImage):** Should be near-instantaneous (**< 15ms**) ensuring the UI never stutters when the popup is presented.
- **Memory Footprint:** The combined peak delta should not trigger an OutOfMemoryError (OOM) on either platform. The Android limit is strictly bounded by the 5MB payload cutoff.
