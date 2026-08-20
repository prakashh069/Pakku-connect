import Cocoa
import FlutterMacOS

class FileTransferPanelController {
    static let shared = FileTransferPanelController()

    private var panel: NSPanel?
    private var methodChannel: FlutterMethodChannel?

    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!
    
    private var copyButton: NSButton!
    private var downloadButton: NSButton!
    private var dismissButton: NSButton!

    private var currentFilePaths: [String]?
    private var currentFileName: String?
    private var currentFolderPath: String?
    private var downloadedUrls: [URL]?
    private var dismissWorkItem: DispatchWorkItem?
    
    private var lastProgressValue: Int = -1

    private init() {}

    func setup(binaryMessenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.connecto.app/fileTransferPopup",
            binaryMessenger: binaryMessenger
        )
        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            if call.method == "showFileTransferPopup", let args = call.arguments as? [String: Any] {
                var paths: [String] = []
                if let filePaths = args["filePaths"] as? [String] {
                    paths = filePaths
                } else if let filePath = args["filePath"] as? String {
                    paths = [filePath]
                }
                
                let fileName = args["fileName"] as? String ?? ""
                let isBatchedZip = args["isBatchedZip"] as? Bool ?? false
                let folderPath = args["folderPath"] as? String
                
                if !paths.isEmpty {
                    self?.showPopup(filePaths: paths, fileName: fileName, isBatchedZip: isBatchedZip, folderPath: folderPath)
                }
                result(nil)
            } else if call.method == "updateFileTransferProgress", let args = call.arguments as? [String: Any] {
                let progress = args["progress"] as? Double ?? 0.0
                let fileName = args["fileName"] as? String ?? ""
                let isBatchedZip = args["isBatchedZip"] as? Bool ?? false
                let batchCount = args["batchCount"] as? Int
                let isDocumentComplete = args["isDocumentComplete"] as? Bool ?? false
                
                self?.updateProgress(progress: progress, fileName: fileName, isBatchedZip: isBatchedZip, batchCount: batchCount, isDocumentComplete: isDocumentComplete)
                result(nil)
            } else if call.method == "showFileTransferError", let args = call.arguments as? [String: Any] {
                // Future use: Error UI endpoint
                let reason = args["reason"] as? String ?? "Unknown error"
                self?.showError(reason: reason)
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func updateProgress(progress: Double, fileName: String, isBatchedZip: Bool, batchCount: Int?, isDocumentComplete: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.createPanelIfNeeded()
            
            self.copyButton.isHidden = true
            self.downloadButton.isHidden = true
            self.progressIndicator.isHidden = false
            
            // Smooth progress update
            let targetProgress = progress * 100.0
            let currentInt = Int(targetProgress)
            
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.allowsImplicitAnimation = true
                self.progressIndicator.animator().doubleValue = targetProgress
            }
            
            // Prevent text flickering
            if currentInt != self.lastProgressValue {
                self.lastProgressValue = currentInt
                
                self.titleLabel.stringValue = "Connecto"
                self.titleLabel.textColor = .labelColor
                
                let isPdfOrDoc = fileName.lowercased().hasSuffix(".pdf") || fileName.lowercased().hasSuffix(".doc") || fileName.lowercased().hasSuffix(".docx") || fileName.lowercased().hasSuffix(".txt") || fileName.lowercased().hasSuffix(".xls") || fileName.lowercased().hasSuffix(".csv") || fileName.lowercased().hasSuffix(".mp4")
                let isSharedFilesZip = fileName.lowercased().hasPrefix("shared_files_")
                
                let fileTypeStr = (isPdfOrDoc || isSharedFilesZip) ? "File" : "Image"
                let fileTypeStrPlural = (isPdfOrDoc || isSharedFilesZip) ? "Files" : "Images"
                
                if isDocumentComplete {
                    self.subtitleLabel.stringValue = "Download Complete"
                    self.subtitleLabel.textColor = .systemGreen
                    self.detailLabel.stringValue = fileName
                    self.scheduleDismiss(delay: 3.0)
                } else {
                    if isBatchedZip, let count = batchCount {
                        self.subtitleLabel.stringValue = "Receiving \(count) \(fileTypeStrPlural)..."
                        self.subtitleLabel.textColor = .systemGreen
                        self.detailLabel.stringValue = "\(currentInt)%"
                    } else {
                        self.subtitleLabel.stringValue = "Receiving \(fileTypeStr)..."
                        self.subtitleLabel.textColor = .systemGreen
                        self.detailLabel.stringValue = fileName
                    }
                }
            }

            self.dismissWorkItem?.cancel()

            guard let p = self.panel else { return }
            if p.isVisible { return }

            let targetOrigin = self.getTargetOrigin()
            p.alphaValue = 0.0
            p.setFrameOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y - 15))
            p.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                p.animator().alphaValue = 1.0
                p.animator().setFrameOrigin(targetOrigin)
            }
        }
    }

    func showPopup(filePaths: [String], fileName: String, isBatchedZip: Bool, folderPath: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.createPanelIfNeeded()
            
            self.currentFilePaths = filePaths
            self.currentFolderPath = folderPath
            self.downloadedUrls = nil // Reset state
            
            self.progressIndicator.isHidden = true
            self.lastProgressValue = -1 // Reset
            
            let isPdfOrDoc = fileName.lowercased().hasSuffix(".pdf") || fileName.lowercased().hasSuffix(".doc") || fileName.lowercased().hasSuffix(".docx") || fileName.lowercased().hasSuffix(".txt") || fileName.lowercased().hasSuffix(".xls") || fileName.lowercased().hasSuffix(".csv") || fileName.lowercased().hasSuffix(".mp4")
            let isSharedFilesZip = fileName.lowercased().hasPrefix("shared_files_")
            let isAutoSave = isPdfOrDoc || isBatchedZip || isSharedFilesZip
            
            let fileTypeStrPlural = (isPdfOrDoc || isSharedFilesZip) ? "Files" : "Images"
            
            self.titleLabel.stringValue = "Connecto"
            self.titleLabel.textColor = .labelColor
            
            if isAutoSave {
                self.downloadedUrls = self.executeSaveLogic()
                self.subtitleLabel.stringValue = "✓ Saved to Downloads"
                self.subtitleLabel.textColor = .systemGreen
                
                self.copyButton.isHidden = true
                self.downloadButton.isHidden = false
                self.downloadButton.frame = NSRect(x: 110, y: 16, width: 120, height: 28) // Centered
                
                self.downloadButton.title = "Open Folder"
                self.downloadButton.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
                self.downloadButton.contentTintColor = .labelColor
                self.downloadButton.action = #selector(self.openClicked)
                
                if isBatchedZip {
                    self.detailLabel.stringValue = "\(filePaths.count) \(fileTypeStrPlural) Received"
                } else {
                    self.detailLabel.stringValue = fileName
                }
            } else {
                self.subtitleLabel.stringValue = "✓ Transfer Complete"
                self.subtitleLabel.textColor = .systemGreen
                
                self.copyButton.isHidden = false
                self.downloadButton.isHidden = false
                self.copyButton.frame = NSRect(x: 60, y: 16, width: 105, height: 28)
                self.downloadButton.frame = NSRect(x: 175, y: 16, width: 105, height: 28)
                
                self.downloadButton.title = "Download"
                self.downloadButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
                self.downloadButton.contentTintColor = .white
                self.downloadButton.action = #selector(self.downloadClicked)
                
                self.detailLabel.stringValue = fileName
            }

            self.scheduleDismiss(delay: 10.0)

            guard let p = self.panel else { return }
            if p.isVisible { return }

            let targetOrigin = self.getTargetOrigin()
            p.alphaValue = 0.0
            p.setFrameOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y - 15))
            p.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                p.animator().alphaValue = 1.0
                p.animator().setFrameOrigin(targetOrigin)
            }
        }
    }
    
    // Future Error UI Implementation
    func showError(reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.createPanelIfNeeded()
            
            self.progressIndicator.isHidden = true
            self.copyButton.isHidden = true
            self.downloadButton.isHidden = false
            
            self.downloadButton.title = "Dismiss"
            self.downloadButton.layer?.backgroundColor = NSColor.systemRed.cgColor
            self.downloadButton.action = #selector(self.dismissClicked)
            self.downloadButton.frame = NSRect(x: 110, y: 16, width: 120, height: 28)
            
            self.titleLabel.stringValue = "Connecto"
            self.subtitleLabel.stringValue = "Transfer Failed"
            self.subtitleLabel.textColor = .systemRed
            self.detailLabel.stringValue = reason
            
            self.scheduleDismiss(delay: 8.0)
            
            guard let p = self.panel else { return }
            if !p.isVisible {
                let targetOrigin = self.getTargetOrigin()
                p.alphaValue = 0.0
                p.setFrameOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y - 15))
                p.orderFrontRegardless()
                
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.5
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                    p.animator().alphaValue = 1.0
                    p.animator().setFrameOrigin(targetOrigin)
                }
            }
        }
    }

    private func createPanelIfNeeded() {
        if panel != nil { return }

        let width: CGFloat  = 340
        let height: CGFloat = 130
        let rect = NSRect(x: 0, y: 0, width: width, height: height)

        let p = NSPanel(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.level               = .popUpMenu
        p.collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate   = false
        p.isOpaque            = false
        p.backgroundColor     = .clear
        p.hasShadow           = true

        let visualEffect = NSVisualEffectView(frame: rect)
        visualEffect.material       = .popover
        visualEffect.blendingMode   = .behindWindow
        visualEffect.state          = .active
        visualEffect.wantsLayer     = true
        visualEffect.layer?.backgroundColor = NSColor.clear.cgColor
        visualEffect.layer?.cornerRadius  = 20
        visualEffect.layer?.masksToBounds = true

        if #available(macOS 11.0, *) {
            let iconImg   = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)
            let imageView = NSImageView(frame: NSRect(x: 20, y: height - 52, width: 32, height: 32))
            imageView.image        = iconImg
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.contentTintColor = .labelColor
            visualEffect.addSubview(imageView)
        }

        titleLabel = NSTextField(labelWithString: "Connecto")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 64, y: height - 34, width: 240, height: 18)
        visualEffect.addSubview(titleLabel)

        subtitleLabel = NSTextField(labelWithString: "")
        subtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = .labelColor
        subtitleLabel.frame = NSRect(x: 64, y: height - 56, width: 240, height: 18)
        visualEffect.addSubview(subtitleLabel)
        
        detailLabel = NSTextField(labelWithString: "")
        detailLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.frame = NSRect(x: 64, y: height - 76, width: 240, height: 18)
        detailLabel.lineBreakMode = .byTruncatingTail
        visualEffect.addSubview(detailLabel)
        
        let btnHeight: CGFloat = 28
        let margin: CGFloat = 16
        
        progressIndicator = NSProgressIndicator(frame: NSRect(x: 64, y: margin + 4, width: 240, height: 18))
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0.0
        progressIndicator.maxValue = 100.0
        progressIndicator.isHidden = true
        visualEffect.addSubview(progressIndicator)

        copyButton = NSButton(title: "Copy", target: self, action: #selector(copyClicked))
        copyButton.isBordered   = false
        copyButton.wantsLayer   = true
        copyButton.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.1).cgColor
        copyButton.layer?.cornerRadius    = 8
        copyButton.font         = NSFont.systemFont(ofSize: 13, weight: .medium)
        copyButton.contentTintColor = .labelColor
        visualEffect.addSubview(copyButton)

        downloadButton = NSButton(title: "Download", target: self, action: #selector(downloadClicked))
        downloadButton.isBordered   = false
        downloadButton.wantsLayer   = true
        downloadButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
        downloadButton.layer?.cornerRadius    = 8
        downloadButton.font         = NSFont.systemFont(ofSize: 13, weight: .medium)
        downloadButton.contentTintColor = .white
        visualEffect.addSubview(downloadButton)
        
        dismissButton = NSButton(title: "✕", target: self, action: #selector(dismissClicked))
        dismissButton.isBordered   = false
        dismissButton.wantsLayer   = true
        dismissButton.font         = NSFont.systemFont(ofSize: 12, weight: .bold)
        dismissButton.contentTintColor = .secondaryLabelColor
        dismissButton.frame = NSRect(x: width - 30, y: height - 30, width: 20, height: 20)
        visualEffect.addSubview(dismissButton)

        p.contentView = visualEffect
        panel = p
    }

    private func getTargetOrigin() -> NSPoint {
        guard let p = panel, let screen = NSScreen.main else { return .zero }
        let sr = screen.visibleFrame
        let padding: CGFloat = 24
        return NSPoint(
            x: sr.maxX - p.frame.width - padding,
            y: sr.maxY - p.frame.height - padding
        )
    }

    @objc private func copyClicked() {
        self.dismissWorkItem?.cancel() // Prevent dismiss while interacting
        
        guard let paths = currentFilePaths, !paths.isEmpty else {
            return
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        var urls: [NSURL] = []
        var images: [NSImage] = []
        
        for path in paths {
            urls.append(NSURL(fileURLWithPath: path))
            if let image = NSImage(contentsOfFile: path) {
                images.append(image)
            }
        }
        
        pasteboard.writeObjects(urls)
        if !images.isEmpty {
            pasteboard.writeObjects(images)
        }
        
        let transition = CATransition()
        transition.duration = 0.25
        transition.type = .fade
        self.copyButton.layer?.add(transition, forKey: "titleFade")
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            self.copyButton.animator().title = "✓ Copied"
            self.copyButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
            self.copyButton.contentTintColor = .white
        }
        
        scheduleDismiss(delay: 2.0)
    }

    @discardableResult
    private func executeSaveLogic() -> [URL]? {
        guard let paths = currentFilePaths, !paths.isEmpty else { return nil }
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let connectoDir = homeDir.appendingPathComponent("Downloads/Connecto")
        
        do {
            if !fileManager.fileExists(atPath: connectoDir.path) {
                try fileManager.createDirectory(at: connectoDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            var finalUrls: [URL] = []
            for path in paths {
                let sourceUrl = URL(fileURLWithPath: path)
                let fileName = sourceUrl.lastPathComponent
                var destUrl = connectoDir.appendingPathComponent(fileName)
                
                var counter = 2
                while fileManager.fileExists(atPath: destUrl.path) {
                    let name = sourceUrl.deletingPathExtension().lastPathComponent
                    let ext = sourceUrl.pathExtension
                    let newName = ext.isEmpty ? "\(name)_\(counter)" : "\(name)_\(counter).\(ext)"
                    destUrl = connectoDir.appendingPathComponent(newName)
                    counter += 1
                }
                
                if fileManager.fileExists(atPath: sourceUrl.path) {
                    try fileManager.moveItem(at: sourceUrl, to: destUrl)
                    
                    let quarantineString = "0081;\(String(format: "%08x", Int(Date().timeIntervalSince1970)));Connecto;"
                    if let quarantineData = quarantineString.data(using: .utf8) {
                        setxattr(destUrl.path, "com.apple.quarantine", (quarantineData as NSData).bytes, quarantineData.count, 0, 0)
                    }
                    
                    finalUrls.append(destUrl)
                }
            }
            return finalUrls
        } catch {
            return nil
        }
    }

    @objc private func downloadClicked() {
        self.dismissWorkItem?.cancel() // Pause dismiss
        
        if self.downloadedUrls == nil {
            self.downloadedUrls = executeSaveLogic()
        }
        
        if self.downloadedUrls != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                    
                    let transition1 = CATransition()
                    transition1.duration = 0.25
                    transition1.type = .fade
                    self.downloadButton.layer?.add(transition1, forKey: "titleFade1")
                    
                    // State 1: ✓ Saved
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.25
                        self.downloadButton.animator().title = "✓ Saved"
                        self.downloadButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
                    }
                    
                    // State 2: Open Folder
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if let panel = self.panel, panel.isVisible {
                            let transition2 = CATransition()
                            transition2.duration = 0.25
                            transition2.type = .fade
                            self.downloadButton.layer?.add(transition2, forKey: "titleFade2")
                            
                            NSAnimationContext.runAnimationGroup { ctx in
                                ctx.duration = 0.25
                                self.downloadButton.animator().title = "Open Folder"
                                self.downloadButton.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
                                self.downloadButton.contentTintColor = .labelColor
                            }
                            self.downloadButton.action = #selector(self.openClicked)
                            self.scheduleDismiss(delay: 5.0)
                        }
                    }
            }
        } else {
            scheduleDismiss(delay: 1.0)
        }
    }
    
    @objc private func openClicked() {
        self.dismissWorkItem?.cancel()
        if let urls = downloadedUrls {
            if urls.count > 1 {
                if let first = urls.first {
                    NSWorkspace.shared.activateFileViewerSelecting([first.deletingLastPathComponent()])
                }
            } else if let first = urls.first {
                let ext = first.pathExtension.lowercased()
                let executableExts = ["app", "command", "sh", "zsh", "bash", "pkg", "dmg", "scpt", "applescript", "py", "pl", "rb", "jar", "exe", "bat"]
                
                if executableExts.contains(ext) {
                    NSWorkspace.shared.activateFileViewerSelecting([first])
                } else {
                    NSWorkspace.shared.open(first)
                }
            }
        }
        dismissPanel()
    }

    @objc private func dismissClicked() {
        dismissWorkItem?.cancel()
        dismissPanel()
    }
    
    private func scheduleDismiss(delay: TimeInterval) {
        dismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.dismissPanel()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func dismissPanel() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let p = self.panel, p.isVisible else { return }
            
            // Implicit auto-save removed per user request for single images.
            // Other file types are already auto-saved in showPopup.
            
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3 // Faster drop out
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.7, 0.0, 0.84, 0.0) // Smooth ease-in
                p.animator().alphaValue = 0.0
                let origin = p.frame.origin
                p.animator().setFrameOrigin(NSPoint(x: origin.x, y: origin.y - 15)) // Drops down slightly
            }, completionHandler: {
                p.orderOut(nil)
                
                // Reset frame to correct position after dismiss
                p.setFrameOrigin(self.getTargetOrigin())
                
                self.currentFilePaths = nil
                self.currentFileName = nil
                
                // Reset button appearances
                self.copyButton.title = "Copy"
                self.copyButton.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.1).cgColor
                self.copyButton.contentTintColor = .labelColor
                
                self.downloadButton.title = "Download"
                self.downloadButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
                self.downloadButton.contentTintColor = .white
            })
        }
    }
}
