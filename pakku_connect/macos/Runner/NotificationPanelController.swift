import Cocoa
import FlutterMacOS
import UserNotifications

class NotificationPanelController: NSObject, UNUserNotificationCenterDelegate {
    private var methodChannel: FlutterMethodChannel?

    init(binaryMessenger: FlutterBinaryMessenger) {
        super.init()
        methodChannel = FlutterMethodChannel(name: "com.connecto.app/notifications", binaryMessenger: binaryMessenger)
        
        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "showNotification":
                if let args = call.arguments as? [String: Any],
                   let title = args["title"] as? String,
                   let body = args["body"] as? String {
                    self?.showLocalNotification(title: title, body: body)
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing title or body", details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // Request permissions
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }
    }

    private func showLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error.localizedDescription)")
            }
        }
    }
    
    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                willPresent notification: UNNotification, 
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
