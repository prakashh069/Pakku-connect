import Cocoa
import FlutterMacOS

class CallPanelController {
    static let shared = CallPanelController()
    
    private var panel: NSPanel?
    private var methodChannel: FlutterMethodChannel?
    
    // UI Elements
    private var nameLabel: NSTextField!
    private var subtitleLabel: NSTextField! // Shows number, then number + timer
    private var initialLabel: NSTextField!
    private var acceptButton: NSButton!
    private var declineButton: NSButton!
    
    // State
    private var currentNumber: String = ""
    
    private init() {}
    
    func setup(binaryMessenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(name: "com.pakku.connect/callPanel", binaryMessenger: binaryMessenger)
        
        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "showCall":
                if let args = call.arguments as? [String: Any] {
                    let name = args["name"] as? String ?? "Unknown"
                    let number = args["number"] as? String ?? "Unknown"
                    self?.showCall(name: name, number: number)
                }
                result(nil)
            case "updateCall":
                if let args = call.arguments as? [String: Any] {
                    let state = args["state"] as? String ?? ""
                    let elapsed = args["elapsedSeconds"] as? Int ?? 0
                    self?.updateCall(state: state, elapsedSeconds: elapsed)
                }
                result(nil)
            case "dismissCall":
                self?.dismissCall()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    private func createPanelIfNeeded() {
        if panel != nil { return }
        
        let width: CGFloat = 340
        let height: CGFloat = 76
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        
        let p = NSPanel(contentRect: rect,
                        styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                        backing: .buffered,
                        defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        
        let visualEffect = NSVisualEffectView(frame: rect)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.masksToBounds = true
        
        // Avatar circle
        let avatarView = NSView(frame: NSRect(x: 16, y: 13, width: 50, height: 50))
        avatarView.wantsLayer = true
        avatarView.layer?.cornerRadius = 25
        avatarView.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.5).cgColor
        
        initialLabel = NSTextField(labelWithString: "U")
        initialLabel.font = NSFont.systemFont(ofSize: 22, weight: .medium)
        initialLabel.textColor = .white
        initialLabel.alignment = .center
        initialLabel.frame = NSRect(x: 0, y: 10, width: 50, height: 30)
        avatarView.addSubview(initialLabel)
        
        // Name Label
        nameLabel = NSTextField(labelWithString: "Unknown")
        nameLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.alignment = .left
        nameLabel.frame = NSRect(x: 76, y: 40, width: 170, height: 22)
        
        // Subtitle Label
        subtitleLabel = NSTextField(labelWithString: "")
        subtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        subtitleLabel.alignment = .left
        subtitleLabel.frame = NSRect(x: 76, y: 20, width: 170, height: 20)
        
        // Buttons
        let btnWidth: CGFloat = 64
        let btnHeight: CGFloat = 26
        let rightMargin: CGFloat = 16
        
        acceptButton = NSButton(title: "", target: self, action: #selector(acceptClicked))
        acceptButton.isBordered = false
        acceptButton.wantsLayer = true
        acceptButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
        acceptButton.layer?.cornerRadius = 6
        if #available(macOS 11.0, *) {
            acceptButton.image = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: nil)
            acceptButton.contentTintColor = .white
            acceptButton.imagePosition = .imageOnly
        }
        acceptButton.frame = NSRect(x: width - rightMargin - btnWidth, y: 41, width: btnWidth, height: btnHeight)
        
        declineButton = NSButton(title: "", target: self, action: #selector(declineClicked))
        declineButton.isBordered = false
        declineButton.wantsLayer = true
        declineButton.layer?.backgroundColor = NSColor.systemRed.cgColor
        declineButton.layer?.cornerRadius = 6
        if #available(macOS 11.0, *) {
            declineButton.image = NSImage(systemSymbolName: "phone.down.fill", accessibilityDescription: nil)
            declineButton.contentTintColor = .white
            declineButton.imagePosition = .imageOnly
        }
        declineButton.frame = NSRect(x: width - rightMargin - btnWidth, y: 9, width: btnWidth, height: btnHeight)
        
        visualEffect.addSubview(avatarView)
        visualEffect.addSubview(nameLabel)
        visualEffect.addSubview(subtitleLabel)
        visualEffect.addSubview(acceptButton)
        visualEffect.addSubview(declineButton)
        
        p.contentView = visualEffect
        panel = p
    }
    
    private func positionPanel() {
        guard let p = panel, let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let padding: CGFloat = 20
        
        let targetX = screenRect.maxX - p.frame.width - padding
        let targetY = screenRect.maxY - p.frame.height - padding
        
        p.setFrameOrigin(NSPoint(x: targetX, y: targetY))
    }
    
    func showCall(name: String, number: String) {
        DispatchQueue.main.async {
            self.createPanelIfNeeded()
            
            let cleanName = name.trimmingCharacters(in: .whitespaces)
            let cleanNumber = number.trimmingCharacters(in: .whitespaces)
            self.currentNumber = cleanNumber
            
            // Name line: contact name, or "Unknown" if none
            let hasRealName = !cleanName.isEmpty && cleanName != cleanNumber && cleanName != "Unknown"
            if hasRealName {
                self.nameLabel.stringValue = cleanName
                self.initialLabel.stringValue = String(cleanName.prefix(1)).uppercased()
            } else {
                self.nameLabel.stringValue = "Unknown"
                self.initialLabel.stringValue = "?"
            }
            
            // Subtitle line: always the phone number
            self.subtitleLabel.stringValue = cleanNumber
            
            self.acceptButton.isHidden = false
            
            guard let p = self.panel else { return }
            
            if !p.isVisible {
                self.positionPanel()
                p.alphaValue = 0.0
                p.orderFrontRegardless()
                
                let originalOrigin = p.frame.origin
                p.setFrameOrigin(NSPoint(x: originalOrigin.x, y: originalOrigin.y + 10))
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    p.animator().alphaValue = 1.0
                    p.animator().setFrameOrigin(originalOrigin)
                }
            }
        }
    }
    
    func updateCall(state: String, elapsedSeconds: Int) {
        DispatchQueue.main.async {
            guard let p = self.panel, p.isVisible else { return }
            
            if state == "answeredRemotely" || state == "answered" {
                // Hide accept, decline stays in its original fixed position
                self.acceptButton.isHidden = true
                
                let mins = elapsedSeconds / 60
                let secs = elapsedSeconds % 60
                let timeString = String(format: "%02d:%02d", mins, secs)
                
                // Subtitle: number + timer
                if self.currentNumber.isEmpty {
                    self.subtitleLabel.stringValue = "In Call • \(timeString)"
                } else {
                    self.subtitleLabel.stringValue = "\(self.currentNumber) • \(timeString)"
                }
            }
        }
    }
    
    func dismissCall() {
        DispatchQueue.main.async {
            guard let p = self.panel, p.isVisible else { return }
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                p.animator().alphaValue = 0.0
                
                let currentOrigin = p.frame.origin
                p.animator().setFrameOrigin(NSPoint(x: currentOrigin.x, y: currentOrigin.y + 10))
            }, completionHandler: {
                p.orderOut(nil)
            })
        }
    }
    
    @objc private func acceptClicked() {
        methodChannel?.invokeMethod("acceptCall", arguments: nil)
    }
    
    @objc private func declineClicked() {
        methodChannel?.invokeMethod("declineCall", arguments: nil)
    }
}
