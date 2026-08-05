import Cocoa
import FlutterMacOS

class CallPanelController {
    static let shared = CallPanelController()
    
    private var panel: NSPanel?
    private var methodChannel: FlutterMethodChannel?
    
    // UI Elements
    private var titleLabel: NSTextField!
    private var nameLabel: NSTextField!
    private var durationLabel: NSTextField!
    private var acceptButton: NSButton!
    private var declineButton: NSButton!
    
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
        
        let width: CGFloat = 300
        let height: CGFloat = 160
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
        
        titleLabel = NSTextField(labelWithString: "Incoming Call")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 10, y: height - 30, width: width - 20, height: 20)
        
        nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        nameLabel.textColor = .labelColor
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 10, y: height - 65, width: width - 20, height: 30)
        
        durationLabel = NSTextField(labelWithString: "")
        durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        durationLabel.textColor = .labelColor
        durationLabel.alignment = .center
        durationLabel.frame = NSRect(x: 10, y: height - 90, width: width - 20, height: 20)
        durationLabel.isHidden = true
        
        let buttonWidth: CGFloat = 120
        let buttonHeight: CGFloat = 36
        let yPos: CGFloat = 20
        
        acceptButton = NSButton(title: "Accept", target: self, action: #selector(acceptClicked))
        acceptButton.bezelStyle = .rounded
        if #available(macOS 14.0, *) {
            acceptButton.contentTintColor = .systemGreen
        }
        acceptButton.frame = NSRect(x: 20, y: yPos, width: buttonWidth, height: buttonHeight)
        
        declineButton = NSButton(title: "Decline", target: self, action: #selector(declineClicked))
        declineButton.bezelStyle = .rounded
        if #available(macOS 14.0, *) {
            declineButton.contentTintColor = .systemRed
        }
        declineButton.frame = NSRect(x: width - 20 - buttonWidth, y: yPos, width: buttonWidth, height: buttonHeight)
        
        visualEffect.addSubview(titleLabel)
        visualEffect.addSubview(nameLabel)
        visualEffect.addSubview(durationLabel)
        visualEffect.addSubview(acceptButton)
        visualEffect.addSubview(declineButton)
        
        p.contentView = visualEffect
        panel = p
    }
    
    private func positionPanel() {
        guard let p = panel, let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let padding: CGFloat = 20
        
        // Target position: top right
        let targetX = screenRect.maxX - p.frame.width - padding
        let targetY = screenRect.maxY - p.frame.height - padding
        
        p.setFrameOrigin(NSPoint(x: targetX, y: targetY))
    }
    
    func showCall(name: String, number: String) {
        DispatchQueue.main.async {
            self.createPanelIfNeeded()
            
            self.titleLabel.stringValue = "Incoming Call"
            
            let cleanName = name.trimmingCharacters(in: .whitespaces)
            let cleanNumber = number.trimmingCharacters(in: .whitespaces)
            
            if cleanName.isEmpty || cleanName == cleanNumber || cleanName == "Unknown" {
                self.nameLabel.stringValue = cleanNumber
            } else {
                self.nameLabel.stringValue = "\(cleanName) • \(cleanNumber)"
            }
            
            self.durationLabel.isHidden = true
            self.acceptButton.isHidden = false
            
            // Reset decline button position & title
            let buttonWidth: CGFloat = 120
            let buttonHeight: CGFloat = 36
            let yPos: CGFloat = 20
            let width: CGFloat = 300
            self.declineButton.frame = NSRect(x: width - 20 - buttonWidth, y: yPos, width: buttonWidth, height: buttonHeight)
            self.declineButton.title = "Decline"
            
            guard let p = self.panel else { return }
            
            if !p.isVisible {
                self.positionPanel()
                
                // Animate entrance: Slide down slightly & fade in
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
                self.titleLabel.stringValue = "Call in progress"
                self.acceptButton.isHidden = true
                self.durationLabel.isHidden = false
                
                // Keep Decline button centered
                let buttonWidth: CGFloat = 120
                let buttonHeight: CGFloat = 36
                let yPos: CGFloat = 20
                let width: CGFloat = 300
                self.declineButton.frame = NSRect(x: (width - buttonWidth) / 2, y: yPos, width: buttonWidth, height: buttonHeight)
                self.declineButton.title = "End Call"
                
                let mins = elapsedSeconds / 60
                let secs = elapsedSeconds % 60
                self.durationLabel.stringValue = String(format: "%02d:%02d", mins, secs)
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
