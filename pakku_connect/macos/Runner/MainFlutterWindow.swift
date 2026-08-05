import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    
    // Prevent the window from being deallocated when closed
    self.isReleasedWhenClosed = false

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
        appDelegate.setupChannels(flutterViewController: flutterViewController, window: self)
    }

    super.awakeFromNib()
  }
}
