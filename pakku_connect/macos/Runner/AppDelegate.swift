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
      
      flutterMethodChannel = FlutterMethodChannel(name: "com.pakku.connect/menuBar",
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
      button.title = "Pakku Connect"
    }
    
    let menu = NSMenu()
    
    statusMenuItem = NSMenuItem(title: "● Disconnected", action: nil, keyEquivalent: "")
    statusMenuItem?.isEnabled = false
    menu.addItem(statusMenuItem!)
    
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Open Pakku Connect", action: #selector(openApp), keyEquivalent: "o"))
    
    toggleConnectionMenuItem = NSMenuItem(title: "Pause Connection", action: #selector(toggleConnection), keyEquivalent: "p")
    menu.addItem(toggleConnectionMenuItem!)
    
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Quit Pakku Connect", action: #selector(quitApp), keyEquivalent: "q"))
    
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
