import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var statusItem: NSStatusItem?
  var flutterMethodChannel: FlutterMethodChannel?
  var currentState: String = "disconnected"
  
  var statusMenuItem: NSMenuItem?
  var toggleConnectionMenuItem: NSMenuItem?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(self)
    }
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    setupMenuBar()
  }

  func setupChannels(flutterViewController: FlutterViewController, window: NSWindow) {
      mainFlutterWindow = window
      
      flutterMethodChannel = FlutterMethodChannel(name: "com.connecto.app/menuBar",
                                                  binaryMessenger: flutterViewController.engine.binaryMessenger)
      
      flutterMethodChannel?.setMethodCallHandler({ [weak self] (call, result) in
        if call.method == "updateStatus", let args = call.arguments as? [String: Any], let state = args["state"] as? String {
            self?.updateMenuBarStatus(state: state)
            result(nil)
        } else if call.method == "checkWindowVisibility" {
            let isAppHidden = NSApp.isHidden
            let isWindowVisible = self?.mainFlutterWindow?.isVisible == true
            let isWindowMiniaturized = self?.mainFlutterWindow?.isMiniaturized == true
            let isOnActiveSpace = self?.mainFlutterWindow?.isOnActiveSpace ?? false
            let isAppActive = NSApp.isActive
            
            let isVisible = !isAppHidden && isWindowVisible && !isWindowMiniaturized && isOnActiveSpace && isAppActive
            result(isVisible)
        } else {
            result(FlutterMethodNotImplemented)
        }
      })
      
      CallPanelController.shared.setup(binaryMessenger: flutterViewController.engine.binaryMessenger)
      ClipboardPanelController.shared.setup(binaryMessenger: flutterViewController.engine.binaryMessenger)
      MacClipboardSync.shared.setup(binaryMessenger: flutterViewController.engine.binaryMessenger)
      NotificationPanelController.shared.setup(binaryMessenger: flutterViewController.engine.binaryMessenger)
      
      NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.didBecomeKeyNotification, object: mainFlutterWindow)
      NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.didResignKeyNotification, object: mainFlutterWindow)
      NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.didMiniaturizeNotification, object: mainFlutterWindow)
      NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.didDeminiaturizeNotification, object: mainFlutterWindow)
      NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.willCloseNotification, object: mainFlutterWindow)
      
      NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSApplication.didHideNotification, object: NSApp)
      NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSApplication.didUnhideNotification, object: NSApp)
      NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSApplication.didBecomeActiveNotification, object: NSApp)
      NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSApplication.didResignActiveNotification, object: NSApp)
      
      NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
  }

  func setupMenuBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    if let button = statusItem?.button {
      button.title = "Connecto"
    }
    
    let menu = NSMenu()
    
    statusMenuItem = NSMenuItem(title: "● Disconnected", action: nil, keyEquivalent: "")
    statusMenuItem?.isEnabled = false
    menu.addItem(statusMenuItem!)
    
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Open Connecto", action: #selector(openApp), keyEquivalent: "o"))
    
    toggleConnectionMenuItem = NSMenuItem(title: "Pause Connection", action: #selector(toggleConnection), keyEquivalent: "p")
    menu.addItem(toggleConnectionMenuItem!)
    
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Quit Connecto", action: #selector(quitApp), keyEquivalent: "q"))
    
    statusItem?.menu = menu
    updateMenuBarStatus(state: "disconnected")
  }

  func updateMenuBarStatus(state: String) {
    self.currentState = state
    
    let statusString: String
    switch state {
    case "connected": statusString = "● Connected"
    case "connecting": statusString = "● Connecting..."
    case "reconnecting": statusString = "● Reconnecting..."
    case "paused": statusString = "● Paused"
    default: statusString = "● Disconnected"
    }

    statusMenuItem?.title = statusString
    
    if state == "paused" {
        toggleConnectionMenuItem?.title = "Resume Connection"
        toggleConnectionMenuItem?.keyEquivalent = "r"
    } else {
        toggleConnectionMenuItem?.title = "Pause Connection"
        toggleConnectionMenuItem?.keyEquivalent = "p"
    }
  }

  @objc func openApp() {
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    windowVisibilityChanged()
  }

  @objc func windowVisibilityChanged(_ notification: Notification? = nil) {
      if notification?.name == NSWindow.willCloseNotification {
          flutterMethodChannel?.invokeMethod("windowVisibilityChanged", arguments: ["isVisible": false])
          return
      }
      
      let isAppHidden = NSApp.isHidden
      let isWindowVisible = mainFlutterWindow?.isVisible == true
      let isWindowMiniaturized = mainFlutterWindow?.isMiniaturized == true
      let isOnActiveSpace = mainFlutterWindow?.isOnActiveSpace ?? false
      let isAppActive = NSApp.isActive
      
      let isVisible = !isAppHidden && isWindowVisible && !isWindowMiniaturized && isOnActiveSpace && isAppActive
      flutterMethodChannel?.invokeMethod("windowVisibilityChanged", arguments: ["isVisible": isVisible])
  }

  @objc func toggleConnection() {
    if currentState == "paused" {
      flutterMethodChannel?.invokeMethod("resume", arguments: nil)
    } else {
      flutterMethodChannel?.invokeMethod("pause", arguments: nil)
    }
  }

  @objc func quitApp() {
    NSApplication.shared.terminate(self)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
import Cocoa
import FlutterMacOS

class MacClipboardSync {
    static let shared = MacClipboardSync()
    private var methodChannel: FlutterMethodChannel?
    private var lastChangeCount: Int = 0
    var ignoreUntilCount: Int = -1
    private var timer: Timer?

    private init() {}

    func setup(binaryMessenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.connecto.app/macClipboard",
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
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
        
        if currentChangeCount <= ignoreUntilCount {
            return
        }
        
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            // Check if it's actually an image on the clipboard to avoid interpreting files as images unnecessarily
            let types = pasteboard.types ?? []
            let isActualImage = types.contains(.png) || types.contains(.tiff) || types.contains(NSPasteboard.PasteboardType("public.jpeg"))
            
            if isActualImage {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    if let tiffData = image.tiffRepresentation,
                       let bitmapImage = NSBitmapImageRep(data: tiffData),
                       let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                        
                        let base64 = jpegData.base64EncodedString()
                        DispatchQueue.main.async {
                            self?.methodChannel?.invokeMethod("clipboardImageChanged", arguments: base64)
                        }
                    }
                }
                return
            }
        } 
        
        if let text = pasteboard.string(forType: .string) {
            // It's text
            methodChannel?.invokeMethod("clipboardTextChanged", arguments: text)
        }
    }
}

import UserNotifications

class NotificationPanelController: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPanelController()
    private var methodChannel: FlutterMethodChannel?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_ACTION",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a message..."
        )
        let category = UNNotificationCategory(
            identifier: "REPLY_CATEGORY",
            actions: [replyAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func setup(binaryMessenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.connecto.app/notifications",
            binaryMessenger: binaryMessenger
        )
        
        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            if call.method == "showNotification" {
                if let args = call.arguments as? [String: Any],
                   let id = args["id"] as? String,
                   let app = args["app"] as? String,
                   let title = args["title"] as? String,
                   let body = args["body"] as? String,
                   let canReply = args["canReply"] as? Bool {
                    let replyHandle = args["replyHandle"] as? String
                    self?.showNotification(id: id, app: app, title: title, body: body, canReply: canReply, replyHandle: replyHandle, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing required notification fields", details: nil))
                }
            } else if call.method == "removeNotification" {
                if let args = call.arguments as? [String: Any],
                   let id = args["id"] as? String {
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing id for removal", details: nil))
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func showNotification(id: String, app: String, title: String, body: String, canReply: Bool, replyHandle: String?, result: @escaping FlutterResult) {
        let center = UNUserNotificationCenter.current()
        
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                DispatchQueue.main.async { result(FlutterError(code: "PERMISSION_ERROR", message: error.localizedDescription, details: nil)) }
                return
            }
            if !granted {
                DispatchQueue.main.async { result(FlutterError(code: "PERMISSION_DENIED", message: "User denied notification permission", details: nil)) }
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = app
            content.subtitle = title
            content.body = body
            content.sound = UNNotificationSound.default
            content.threadIdentifier = app
            
            if canReply, let handle = replyHandle {
                content.categoryIdentifier = "REPLY_CATEGORY"
                content.userInfo = ["replyHandle": handle]
            }

            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            
            center.add(request) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        result(FlutterError(code: "DELIVERY_ERROR", message: error.localizedDescription, details: nil))
                    } else {
                        result(nil)
                    }
                }
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "REPLY_ACTION",
           let textResponse = response as? UNTextInputNotificationResponse {
            let replyText = textResponse.userText
            let userInfo = response.notification.request.content.userInfo
            if let replyHandle = userInfo["replyHandle"] as? String {
                methodChannel?.invokeMethod("sendReply", arguments: [
                    "replyHandle": replyHandle,
                    "text": replyText
                ])
            }
        }
        completionHandler()
    }
}
