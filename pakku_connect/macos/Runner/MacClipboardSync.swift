import Cocoa
import FlutterMacOS

class MacClipboardSync {
    static let shared = MacClipboardSync()
    private var methodChannel: FlutterMethodChannel?
    private var lastChangeCount: Int = 0
    private var timer: Timer?

    private init() {}

    func setup(binaryMessenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.pakku.connect/macClipboard",
            binaryMessenger: binaryMessenger
        )
        
        lastChangeCount = NSPasteboard.general.changeCount
        
        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            if call.method == "startWatching" {
                self?.startWatching()
                result(nil)
            } else if call.method == "stopWatching" {
                self?.stopWatching()
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    private func startWatching() {
        if timer != nil { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    private func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        
        if currentChangeCount == lastChangeCount {
            return
        }
        
        lastChangeCount = currentChangeCount
        
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            // It's an image
            if let tiffData = image.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                
                let base64 = pngData.base64EncodedString()
                methodChannel?.invokeMethod("clipboardImageChanged", arguments: base64)
            }
        } else if let text = pasteboard.string(forType: .string) {
            // It's text
            methodChannel?.invokeMethod("clipboardTextChanged", arguments: text)
        }
    }
}
