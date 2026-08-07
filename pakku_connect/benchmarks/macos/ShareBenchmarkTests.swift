import Foundation
import AppKit

/// Benchmark Test for macOS Share Pipeline.
/// 
/// Measures:
/// 1. Base64 Decoding Latency
/// 2. Image Decoding (NSImage creation) Latency
/// 3. Clipboard Write Latency
/// 4. Memory Footprint Delta
class ShareBenchmarkTests {
    
    static func runBenchmarks(base64Payload: String) {
        print("=== Pakku Share Framework: macOS Benchmarks ===")
        print("Payload Size: \(base64Payload.count / 1024) KB")
        
        let startMemory = getMemoryUsage()
        
        // 1. Base64 Decoding
        let b64Start = CFAbsoluteTimeGetCurrent()
        guard let data = Data(base64Encoded: base64Payload) else {
            print("Failed to decode base64 payload. Aborting.")
            return
        }
        let b64End = CFAbsoluteTimeGetCurrent()
        print("[Decode] Base64 -> Data: \(String(format: "%.2f", (b64End - b64Start) * 1000))ms")
        
        // 2. NSImage Creation
        let imgStart = CFAbsoluteTimeGetCurrent()
        guard let image = NSImage(data: data) else {
            print("Failed to create NSImage from data. Aborting.")
            return
        }
        // Force evaluation of the image representation
        _ = image.representations
        let imgEnd = CFAbsoluteTimeGetCurrent()
        print("[Decode] Data -> NSImage: \(String(format: "%.2f", (imgEnd - imgStart) * 1000))ms")
        
        let postDecodeMemory = getMemoryUsage()
        print("[Memory] Decode Delta: \(String(format: "%.2f", postDecodeMemory - startMemory)) MB")
        
        // 3. Clipboard Write Latency
        let pasteboard = NSPasteboard.general
        let pbStart = CFAbsoluteTimeGetCurrent()
        pasteboard.clearContents()
        // Assuming JPEG or PNG, we can use the raw data directly to avoid re-encoding
        pasteboard.setData(data, forType: .png) 
        let pbEnd = CFAbsoluteTimeGetCurrent()
        print("[Write] NSPasteboard setData: \(String(format: "%.2f", (pbEnd - pbStart) * 1000))ms")
        
        // 4. Cleanup Memory Delta
        let _ = image // Keep alive until here
        let endMemory = getMemoryUsage()
        print("[Memory] Final Delta (before GC): \(String(format: "%.2f", endMemory - startMemory)) MB")
        print("===============================================")
    }
    
    private static func getMemoryUsage() -> Double {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(taskInfo.resident_size) / (1024.0 * 1024.0)
        } else {
            return 0.0
        }
    }
}
