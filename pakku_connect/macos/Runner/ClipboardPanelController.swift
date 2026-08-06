import Cocoa
import FlutterMacOS

/// Presents clipboard share notifications as a lightweight floating panel.
///
/// Completely standalone — does not extend or modify CallPanelController.
/// Visually matches Pakku's existing call panel design.
///
/// Behaviour:
/// - New id while panel hidden: show panel with slide-up + fade-in
/// - New id while panel visible: replace content, skip animation (newest wins)
/// - Same id arrives: silently ignored
/// - Copy: writes full text to NSPasteboard, shows "✓ Copied", fades after 1.2s
/// - Dismiss: fade-out + slide-up
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
    private var fullText: String = ""
    private var fullImageBase64: String? = nil
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func setup(binaryMessenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.pakku.connect/clipboardShare",
            binaryMessenger: binaryMessenger
        )
        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            if call.method == "showShare",
               let args = call.arguments as? [String: Any] {
                let id          = args["id"]          as? String ?? ""
                let text        = args["text"]        as? String ?? ""
                let imageBase64 = args["imageBase64"] as? String
                let deviceName  = args["deviceName"]  as? String ?? "Android"
                self?.showShare(id: id, text: text, imageBase64: imageBase64, deviceName: deviceName)
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - Public API

    func showShare(id: String, text: String, imageBase64: String?, deviceName: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Deduplicate: same id → silently ignore
            if id == self.currentId { return }

            self.currentId       = id
            self.fullText        = text    // stored untruncated for Copy
            self.fullImageBase64 = imageBase64

            self.createPanelIfNeeded()
            self.updateContent(deviceName: deviceName, text: text, hasImage: imageBase64 != nil)

            // Cancel any pending auto-dismiss (from previous Copy action)
            self.dismissWorkItem?.cancel()
            self.dismissWorkItem = nil

            // Schedule auto-dismiss for 5 seconds
            let work = DispatchWorkItem { [weak self] in
                self?.dismissPanel()
            }
            self.dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)

            guard let p = self.panel else { return }

            if p.isVisible {
                // Panel already visible — replace content, skip animation (rate limiting)
                return
            }

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

    // MARK: - Panel Construction

    private func createPanelIfNeeded() {
        if panel != nil { return }

        let width: CGFloat  = 340
        let height: CGFloat = 76
        let rect = NSRect(x: 0, y: 0, width: width, height: height)

        let p = NSPanel(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.level                 = .floating
        p.collectionBehavior    = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate     = false
        p.isOpaque              = false
        p.backgroundColor       = .clear
        p.hasShadow             = true

        let visualEffect = NSVisualEffectView(frame: rect)
        visualEffect.material       = .hudWindow
        visualEffect.blendingMode   = .behindWindow
        visualEffect.state          = .active
        visualEffect.wantsLayer     = true
        visualEffect.layer?.cornerRadius    = 16
        visualEffect.layer?.masksToBounds   = true

        // Clipboard icon
        let iconView = NSTextField(labelWithString: "")
        if #available(macOS 11.0, *) {
            let iconImg = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
            let imageView = NSImageView(frame: NSRect(x: 16, y: 22, width: 32, height: 32))
            imageView.image          = iconImg
            imageView.imageScaling   = .scaleProportionallyUpOrDown
            if #available(macOS 11.0, *) {
                imageView.contentTintColor = NSColor.white.withAlphaComponent(0.85)
            }
            visualEffect.addSubview(imageView)
        } else {
            iconView.stringValue    = "📋"
            iconView.font           = NSFont.systemFont(ofSize: 22)
            iconView.frame          = NSRect(x: 14, y: 24, width: 36, height: 30)
            visualEffect.addSubview(iconView)
        }

        // Device label (e.g. "📱 Pixel 8")
        deviceLabel = NSTextField(labelWithString: "")
        deviceLabel.font        = NSFont.systemFont(ofSize: 13, weight: .semibold)
        deviceLabel.textColor   = .white
        deviceLabel.frame       = NSRect(x: 58, y: 42, width: 188, height: 18)
        visualEffect.addSubview(deviceLabel)

        // Preview label (truncated display only)
        previewLabel = NSTextField(labelWithString: "")
        previewLabel.font       = NSFont.systemFont(ofSize: 12, weight: .regular)
        previewLabel.textColor  = NSColor.white.withAlphaComponent(0.75)
        previewLabel.frame      = NSRect(x: 58, y: 22, width: 188, height: 18)
        visualEffect.addSubview(previewLabel)

        // Copy button
        let btnWidth:  CGFloat = 64
        let btnHeight: CGFloat = 26
        let rightMargin: CGFloat = 14

        copyButton = NSButton(title: "Copy", target: self, action: #selector(copyClicked))
        copyButton.isBordered   = false
        copyButton.wantsLayer   = true
        copyButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
        copyButton.layer?.cornerRadius    = 6
        copyButton.font         = NSFont.systemFont(ofSize: 12, weight: .medium)
        copyButton.contentTintColor = .white
        copyButton.frame = NSRect(x: width - rightMargin - btnWidth, y: 41, width: btnWidth, height: btnHeight)
        visualEffect.addSubview(copyButton)

        // Dismiss button
        dismissButton = NSButton(title: "Dismiss", target: self, action: #selector(dismissClicked))
        dismissButton.isBordered   = false
        dismissButton.wantsLayer   = true
        dismissButton.layer?.backgroundColor = NSColor(white: 0.4, alpha: 0.6).cgColor
        dismissButton.layer?.cornerRadius    = 6
        dismissButton.font         = NSFont.systemFont(ofSize: 12, weight: .regular)
        dismissButton.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        dismissButton.frame = NSRect(x: width - rightMargin - btnWidth, y: 9, width: btnWidth, height: btnHeight)
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

    private func updateContent(deviceName: String, text: String, hasImage: Bool) {
        deviceLabel.stringValue  = "📱 \(deviceName)"
        if hasImage {
            previewLabel.stringValue = "🖼️ Image"
        } else {
            // Preview truncated to 80 chars for display. fullText is always complete.
            let preview = text.count > 80 ? String(text.prefix(80)) + "…" : text
            // Collapse newlines for single-line preview
            previewLabel.stringValue = preview.components(separatedBy: .newlines).first ?? preview
        }
        copyButton.title         = "Copy"
        copyButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
    }

    // MARK: - Actions

    @objc private func copyClicked() {
        NSPasteboard.general.clearContents()
        
        if let base64 = fullImageBase64, let data = Data(base64Encoded: base64) {
            // Copy image data to the macOS clipboard.
            NSPasteboard.general.setData(data, forType: .png)
        } else {
            // Copy the full, untruncated text to the macOS clipboard.
            NSPasteboard.general.setString(fullText, forType: .string)
        }

        // Show "✓ Copied" confirmation state.
        copyButton.title = "✓ Copied"
        copyButton.layer?.backgroundColor = NSColor.systemTeal.cgColor

        // Auto-dismiss after 1.2 s.
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
                // Reset so next show uses fresh animation
                self.currentId = nil
            })
        }
    }
}
