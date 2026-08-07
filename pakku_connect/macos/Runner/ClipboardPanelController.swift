import Cocoa
import FlutterMacOS

/// Presents share notifications as a lightweight floating panel.
///
/// Completely standalone — does not extend or modify CallPanelController.
///
/// Behaviour:
/// - New id while panel hidden: show panel with slide-up + fade-in
/// - New id while panel visible: replace content, skip animation (newest wins)
/// - Same id arrives: silently ignored
/// - Copy button is disabled until background Base64 decoding finishes
/// - Copy: writes pre-decoded Data to NSPasteboard instantly (no decode on click)
/// - Dismiss: fade-out + slide-up; decoded data is released from memory
///
/// Thread contract:
/// - Base64 decoding runs on DispatchQueue.global (background)
/// - All AppKit/UI updates run on DispatchQueue.main
/// - NSImage creation is lazy: Data alone is used for pasteboard;
///   NSImage is only created if a preview thumbnail is needed
///
/// Memory contract:
/// - Decoded image Data is released when the popup is dismissed or replaced,
///   preventing multi-MB payloads from accumulating in memory.
class ClipboardPanelController {
    static let shared = ClipboardPanelController()

    private var panel: NSPanel?
    private var methodChannel: FlutterMethodChannel?

    // UI elements
    private var deviceLabel: NSTextField!
    private var previewLabel: NSTextField!
    private var copyButton: NSButton!
    private var dismissButton: NSButton!

    // State
    private var currentId: String?
    private var dismissWorkItem: DispatchWorkItem?

    /// Pre-decoded payload ready for pasteboard. nil until decode completes.
    private var decodedData: Data?
    /// Plain text payload for text/plain shares.
    private var plainText: String?
    /// Current share MIME type.
    private var currentMime: String?

    private init() {}

    func setup(binaryMessenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.pakku.connect/clipboardShare",
            binaryMessenger: binaryMessenger
        )
        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            if call.method == "showShare",
               let args = call.arguments as? [String: Any] {
                let id         = args["id"]         as? String ?? ""
                let mime       = args["mime"]       as? String ?? ""
                let deviceName = args["deviceName"] as? String ?? "Android"
                let content    = args["content"]    as? [String: Any] ?? [:]
                self?.showShare(id: id, mime: mime, deviceName: deviceName, content: content)
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - Public API

    func showShare(id: String, mime: String, deviceName: String, content: [String: Any]) {
        // All state updates and UI changes run on main thread.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Deduplicate: same id → silently ignore
            if id == self.currentId { return }

            // Release previous payload from memory immediately (memory contract).
            self.decodedData = nil
            self.plainText   = nil
            self.currentMime = mime.lowercased()
            self.currentId   = id

            self.createPanelIfNeeded()

            // Disable Copy until decode finishes.
            self.copyButton.isEnabled = false
            self.copyButton.alphaValue = 0.5

            let encoding = content["encoding"] as? String ?? ""
            let body     = content["body"]     as? String ?? ""
            let metadata = content["metadata"] as? [String: Any]

            // Build preview info from metadata (advisory only — fallback gracefully).
            let displayName = metadata?["displayName"] as? String
            let width       = metadata?["width"]       as? Int
            let height      = metadata?["height"]      as? Int
            let sizeBytes   = metadata?["sizeBytes"]   as? Int

            self.updateContent(
                deviceName:  deviceName,
                mime:        mime,
                displayName: displayName,
                width:       width,
                height:      height,
                sizeBytes:   sizeBytes,
                body:        body
            )

            // Cancel any pending auto-dismiss.
            self.dismissWorkItem?.cancel()
            self.dismissWorkItem = nil

            // Schedule auto-dismiss for 5 seconds.
            let work = DispatchWorkItem { [weak self] in
                self?.dismissPanel()
            }
            self.dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)

            // Kick off background decode.
            if encoding == "base64" && !body.isEmpty {
                self.decodeBase64InBackground(body: body)
            } else if encoding == "utf-8" {
                // Plain text — no decode needed; enable Copy immediately.
                self.plainText = body
                self.setCopyEnabled(true)
            }

            // Animate panel in (if not already visible).
            guard let p = self.panel else { return }
            if p.isVisible { return }

            self.positionPanel()
            p.alphaValue = 0.0
            p.orderFrontRegardless()

            let origin = p.frame.origin
            p.setFrameOrigin(NSPoint(x: origin.x, y: origin.y + 10))

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().alphaValue = 1.0
                p.animator().setFrameOrigin(origin)
            }
        }
    }

    // MARK: - Background Decode

    private func decodeBase64InBackground(body: String) {
        // Capture the id at dispatch time to guard against stale decodes.
        let capturedId = self.currentId

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Decode off the UI thread.
            guard let data = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else {
                // Decode failure → drop silently per failure contract.
                return
            }

            // Hop back to main thread to update state and UI.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                // Guard: if a newer share arrived while decoding, discard this result.
                guard self.currentId == capturedId else { return }

                self.decodedData = data
                self.setCopyEnabled(true)
            }
        }
    }

    // MARK: - Panel Construction

    private func createPanelIfNeeded() {
        if panel != nil { return }

        let width: CGFloat  = 340
        let height: CGFloat = 96
        let rect = NSRect(x: 0, y: 0, width: width, height: height)

        let p = NSPanel(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.level               = .floating
        p.collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate   = false
        p.isOpaque            = false
        p.backgroundColor     = .clear
        p.hasShadow           = true

        let visualEffect = NSVisualEffectView(frame: rect)
        visualEffect.material       = .hudWindow
        visualEffect.blendingMode   = .behindWindow
        visualEffect.state          = .active
        visualEffect.wantsLayer     = true
        visualEffect.layer?.cornerRadius  = 16
        visualEffect.layer?.masksToBounds = true

        // Icon
        if #available(macOS 11.0, *) {
            let iconImg   = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
            let imageView = NSImageView(frame: NSRect(x: 16, y: 30, width: 32, height: 32))
            imageView.image        = iconImg
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.contentTintColor = .labelColor
            visualEffect.addSubview(imageView)
        }

        // Device label (e.g. "📱 Pixel 8")
        deviceLabel = NSTextField(labelWithString: "")
        deviceLabel.font      = NSFont.systemFont(ofSize: 13, weight: .semibold)
        deviceLabel.textColor = .labelColor
        deviceLabel.frame     = NSRect(x: 58, y: 60, width: 188, height: 18)
        visualEffect.addSubview(deviceLabel)

        // Preview label — two lines of detail
        previewLabel = NSTextField(labelWithString: "")
        previewLabel.font      = NSFont.systemFont(ofSize: 11, weight: .regular)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.frame     = NSRect(x: 58, y: 28, width: 188, height: 32)
        previewLabel.maximumNumberOfLines = 2
        previewLabel.lineBreakMode        = .byTruncatingTail
        visualEffect.addSubview(previewLabel)

        let btnWidth: CGFloat    = 64
        let btnHeight: CGFloat   = 26
        let rightMargin: CGFloat = 14

        // Copy button (disabled until decode finishes)
        copyButton = NSButton(title: "Copy", target: self, action: #selector(copyClicked))
        copyButton.isBordered   = false
        copyButton.wantsLayer   = true
        copyButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
        copyButton.layer?.cornerRadius    = 6
        copyButton.font         = NSFont.systemFont(ofSize: 12, weight: .medium)
        copyButton.contentTintColor = .white
        copyButton.isEnabled    = false
        copyButton.alphaValue   = 0.5
        copyButton.frame = NSRect(x: width - rightMargin - btnWidth, y: 57, width: btnWidth, height: btnHeight)
        visualEffect.addSubview(copyButton)

        // Dismiss button
        dismissButton = NSButton(title: "Dismiss", target: self, action: #selector(dismissClicked))
        dismissButton.isBordered   = false
        dismissButton.wantsLayer   = true
        dismissButton.layer?.backgroundColor = NSColor(white: 0.4, alpha: 0.6).cgColor
        dismissButton.layer?.cornerRadius    = 6
        dismissButton.font         = NSFont.systemFont(ofSize: 12, weight: .regular)
        dismissButton.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        dismissButton.frame = NSRect(x: width - rightMargin - btnWidth, y: 25, width: btnWidth, height: btnHeight)
        visualEffect.addSubview(dismissButton)

        p.contentView = visualEffect
        panel = p
    }

    private func positionPanel() {
        guard let p = panel, let screen = NSScreen.main else { return }
        let sr = screen.visibleFrame
        let padding: CGFloat = 20
        p.setFrameOrigin(NSPoint(
            x: sr.maxX - p.frame.width - padding,
            y: sr.maxY - p.frame.height - padding
        ))
    }

    private func setCopyEnabled(_ enabled: Bool) {
        copyButton.isEnabled  = enabled
        copyButton.alphaValue = enabled ? 1.0 : 0.5
    }

    private func updateContent(deviceName: String, mime: String,
                               displayName: String?, width: Int?,
                               height: Int?, sizeBytes: Int?, body: String) {
        deviceLabel.stringValue = "📱 \(deviceName)"

        let mimeUpper = mime.lowercased()

        if mimeUpper == "text/plain" {
            let previewText = body.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
            previewLabel.stringValue = previewText.count > 60 ? String(previewText.prefix(60)) + "..." : previewText
        } else if mimeUpper.hasPrefix("image/") {
            // Format: "Screenshot\n1080 × 2400  PNG • 2.3 MB"
            let name      = displayName ?? "Image"
            let ext       = mime.components(separatedBy: "/").last?.uppercased() ?? "IMAGE"
            var details   = ext

            if let sizeBytes {
                let sizeMB = Double(sizeBytes) / 1_048_576
                details += " • \(String(format: "%.1f", sizeMB)) MB"
            }

            var line2 = ""
            if let w = width, let h = height {
                line2 = "\(w) × \(h)  \(details)"
            } else {
                line2 = details
            }

            previewLabel.stringValue = "\(name)\n\(line2)"
        } else {
            previewLabel.stringValue = mime
        }

        copyButton.title = "Copy"
        copyButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
    }

    // MARK: - Actions

    @objc private func copyClicked() {
        NSPasteboard.general.clearContents()

        // Copy uses pre-decoded Data only — never decodes Base64 again.
        if let mime = currentMime, mime.hasPrefix("image/"), let data = decodedData {
            let pasteboardType: NSPasteboard.PasteboardType = mime.contains("jpeg")
                ? .init("public.jpeg")
                : .png
            NSPasteboard.general.setData(data, forType: pasteboardType)
        } else if let text = plainText {
            NSPasteboard.general.setString(text, forType: .string)
        }

        copyButton.title = "✓ Copied"
        copyButton.layer?.backgroundColor = NSColor.systemTeal.cgColor

        let work = DispatchWorkItem { [weak self] in
            self?.dismissPanel()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    @objc private func dismissClicked() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        dismissPanel()
    }

    // MARK: - Panel Animation

    private func dismissPanel() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let p = self.panel, p.isVisible else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                p.animator().alphaValue = 0.0
                let origin = p.frame.origin
                p.animator().setFrameOrigin(NSPoint(x: origin.x, y: origin.y + 10))
            }, completionHandler: {
                p.orderOut(nil)
                // Release memory and reset state (memory contract).
                self.currentId   = nil
                self.decodedData = nil
                self.plainText   = nil
                self.currentMime = nil
            })
        }
    }
}
