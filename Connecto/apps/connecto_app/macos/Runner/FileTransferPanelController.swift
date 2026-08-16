import Cocoa
import FlutterMacOS

class FileTransferPanelController {
    static let shared = FileTransferPanelController()

    private var panel: NSPanel?
    private var methodChannel: FlutterMethodChannel?

    private var previewLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!
    private var copyButton: NSButton!
    private var downloadButton: NSButton!
    private var dismissButton: NSButton!

    private var currentFilePaths: [String]?
    private var currentFileName: String?
    private var currentFolderPath: String?
    private var downloadedUrls: [URL]?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func setup(binaryMessenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.connecto.app/fileTransferPopup",
            binaryMessenger: binaryMessenger
        )
        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            if call.method == "showFileTransferPopup", let args = call.arguments as? [String: Any] {
                print("[PHASE7] POPUP METHOD CHANNEL RECEIVED")
                
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
            self.progressIndicator.doubleValue = progress * 100.0
            
            let isPdfOrDoc = fileName.lowercased().hasSuffix(".pdf") || fileName.lowercased().hasSuffix(".doc") || fileName.lowercased().hasSuffix(".docx") || fileName.lowercased().hasSuffix(".txt") || fileName.lowercased().hasSuffix(".xls") || fileName.lowercased().hasSuffix(".csv") || fileName.lowercased().hasSuffix(".mp4")
            
            let fileTypeStr = isPdfOrDoc ? "File" : "Image"
            let fileTypeStrPlural = isPdfOrDoc ? "Files" : "Images"
            
            if isDocumentComplete {
                self.previewLabel.stringValue = "Connecto\nDownload Complete\n\(fileName)"
                self.scheduleDismiss(delay: 3.0)
            } else {
                if isBatchedZip, let count = batchCount {
                    self.previewLabel.stringValue = "Connecto\nReceiving \(count) \(fileTypeStrPlural)\n\(Int(progress * 100))%"
                } else {
                    self.previewLabel.stringValue = "Connecto\nReceiving \(fileTypeStr)\n\(fileName)"
                }
            }

            self.dismissWorkItem?.cancel()

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

    func showPopup(filePaths: [String], fileName: String, isBatchedZip: Bool, folderPath: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.createPanelIfNeeded()
            
            self.currentFilePaths = filePaths
            self.currentFolderPath = folderPath
            
            self.progressIndicator.isHidden = true
            self.copyButton.isHidden = false
            self.downloadButton.isHidden = false
            
            let isPdfOrDoc = fileName.lowercased().hasSuffix(".pdf") || fileName.lowercased().hasSuffix(".doc") || fileName.lowercased().hasSuffix(".docx") || fileName.lowercased().hasSuffix(".txt") || fileName.lowercased().hasSuffix(".xls") || fileName.lowercased().hasSuffix(".csv") || fileName.lowercased().hasSuffix(".mp4")
            let fileTypeStr = isPdfOrDoc ? "File" : "Image"
            let fileTypeStrPlural = isPdfOrDoc ? "Files" : "Images"
            
            // Reset download button
            self.downloadButton.title = "Download"
            self.downloadButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
            self.downloadButton.action = #selector(self.downloadClicked)
            
            if isBatchedZip {
                self.copyButton.isHidden = true
                self.downloadButton.isHidden = false
                self.downloadButton.frame = NSRect(x: 108, y: 14, width: 120, height: 26) // Centered and wider
                self.previewLabel.stringValue = "Connecto\n\(filePaths.count) \(fileTypeStrPlural) Received"
            } else if isPdfOrDoc {
                self.copyButton.isHidden = true
                self.downloadButton.isHidden = false
                self.downloadButton.frame = NSRect(x: 108, y: 14, width: 120, height: 26) // Centered and wider
                self.previewLabel.stringValue = "Connecto\n\(fileTypeStr) Received\n\(fileName)"
            } else {
                self.copyButton.isHidden = false
                self.downloadButton.isHidden = false
                self.copyButton.frame = NSRect(x: 58, y: 14, width: 80, height: 26)
                self.downloadButton.frame = NSRect(x: 58 + 80 + 10, y: 14, width: 80, height: 26)
                self.previewLabel.stringValue = "Connecto\n\(fileTypeStr) Received\n\(fileName)"
            }

            self.dismissWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.dismissPanel()
            }
            self.dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: work)

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

    private func createPanelIfNeeded() {
        if panel != nil { return }

        let width: CGFloat  = 340
        let height: CGFloat = 110
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
        p.hasShadow           = false

        let visualEffect = NSVisualEffectView(frame: rect)
        visualEffect.material       = .popover
        visualEffect.blendingMode   = .behindWindow
        visualEffect.state          = .active
        visualEffect.wantsLayer     = true
        visualEffect.layer?.cornerRadius  = 16
        visualEffect.layer?.masksToBounds = true

        if #available(macOS 11.0, *) {
            let iconImg   = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)
            let imageView = NSImageView(frame: NSRect(x: 16, y: 38, width: 32, height: 32))
            imageView.image        = iconImg
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.contentTintColor = .labelColor
            visualEffect.addSubview(imageView)
        }

        previewLabel = NSTextField(labelWithString: "")
        previewLabel.font      = NSFont.systemFont(ofSize: 12, weight: .regular)
        previewLabel.textColor = .labelColor
        previewLabel.frame     = NSRect(x: 58, y: 38, width: 260, height: 48)
        previewLabel.maximumNumberOfLines = 3
        previewLabel.lineBreakMode        = .byTruncatingTail
        visualEffect.addSubview(previewLabel)
        let btnWidth: CGFloat    = 80
        let btnHeight: CGFloat   = 26
        let margin: CGFloat      = 14
        
        progressIndicator = NSProgressIndicator(frame: NSRect(x: 58, y: margin, width: 200, height: 26))
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0.0
        progressIndicator.maxValue = 100.0
        progressIndicator.isHidden = true
        visualEffect.addSubview(progressIndicator)

        copyButton = NSButton(title: "Copy", target: self, action: #selector(copyClicked))
        copyButton.isBordered   = false
        copyButton.wantsLayer   = true
        copyButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
        copyButton.layer?.cornerRadius    = 6
        copyButton.font         = NSFont.systemFont(ofSize: 12, weight: .medium)
        copyButton.contentTintColor = .white
        copyButton.frame = NSRect(x: 58, y: margin, width: btnWidth, height: btnHeight)
        visualEffect.addSubview(copyButton)

        downloadButton = NSButton(title: "Download", target: self, action: #selector(downloadClicked))
        downloadButton.isBordered   = false
        downloadButton.wantsLayer   = true
        downloadButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
        downloadButton.layer?.cornerRadius    = 6
        downloadButton.font         = NSFont.systemFont(ofSize: 12, weight: .medium)
        downloadButton.contentTintColor = .white
        downloadButton.frame = NSRect(x: 58 + btnWidth + 10, y: margin, width: btnWidth, height: btnHeight)
        visualEffect.addSubview(downloadButton)
        
        dismissButton = NSButton(title: "✕", target: self, action: #selector(dismissClicked))
        dismissButton.isBordered   = false
        dismissButton.wantsLayer   = true
        dismissButton.font         = NSFont.systemFont(ofSize: 14, weight: .bold)
        dismissButton.contentTintColor = .secondaryLabelColor
        dismissButton.frame = NSRect(x: width - 30, y: height - 30, width: 20, height: 20)
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

    @objc private func copyClicked() {
        print("[PHASE7] COPY BUTTON CLICKED")
        guard let paths = currentFilePaths, !paths.isEmpty else {
            print("[PHASE7] ERROR: No file paths to copy")
            return
        }
        
        if paths.count > 1 {
            print("[PHASE8] COPY BATCH CLICKED")
            print("[PHASE8] COPYING FILES:\n\(paths.count)")
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
        
        print("[PHASE7] \(paths.count) FILES COPIED TO CLIPBOARD (\(images.count) IMAGES)")
        
        if paths.count > 1 {
            print("[PHASE8] IMAGES COPIED")
        }
        
        copyButton.title = "Copied"
        copyButton.layer?.backgroundColor = NSColor.systemTeal.cgColor
        
        scheduleDismiss(delay: 1.2)
    }

    @objc private func downloadClicked() {
        print("[PHASE7] DOWNLOAD BUTTON CLICKED")
        
        if let paths = currentFilePaths, !paths.isEmpty {
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
                    
                    try fileManager.moveItem(at: sourceUrl, to: destUrl)
                    finalUrls.append(destUrl)
                }
                
                self.downloadedUrls = finalUrls
                
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.downloadButton.title = "Open"
                    self.downloadButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
                    self.downloadButton.action = #selector(self.openClicked)
                    self.scheduleDismiss(delay: 5.0)
                }
                
                print("[PHASE7] DOWNLOADED \(finalUrls.count) FILES TO CONNECTO FOLDER")
                
            } catch {
                print("[PHASE8] ERROR SAVING FILES: \(error)")
                scheduleDismiss(delay: 0.5)
            }
        } else {
            scheduleDismiss(delay: 0.5)
        }
    }
    
    @objc private func openClicked() {
        print("[PHASE8] OPEN BUTTON CLICKED")
        if let urls = downloadedUrls {
            if urls.count > 1 {
                // If it's a batch, just open the Connecto folder
                if let first = urls.first {
                    NSWorkspace.shared.activateFileViewerSelecting([first.deletingLastPathComponent()])
                }
            } else if let first = urls.first {
                // Open the actual file
                NSWorkspace.shared.open(first)
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
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                p.animator().alphaValue = 0.0
                let origin = p.frame.origin
                p.animator().setFrameOrigin(NSPoint(x: origin.x, y: origin.y + 10))
            }, completionHandler: {
                p.orderOut(nil)
                self.currentFilePaths = nil
                self.currentFileName = nil
                self.copyButton.title = "Copy"
                self.copyButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
            })
        }
    }
}
