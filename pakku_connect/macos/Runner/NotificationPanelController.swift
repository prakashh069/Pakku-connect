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
                    let canReply = args["canReply"] as? Bool ?? false
                    let replyHandle = args["replyHandle"] as? String
                    self?.showLocalNotification(title: title, body: body, canReply: canReply, replyHandle: replyHandle)
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
        
        // Define reply category
        let replyAction = UNTextInputNotificationAction(identifier: "REPLY_ACTION", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Type your reply...")
        let replyCategory = UNNotificationCategory(identifier: "REPLY_CATEGORY", actions: [replyAction], intentIdentifiers: [], options: [])
        center.setNotificationCategories([replyCategory])
    }

    private func showLocalNotification(title: String, body: String, canReply: Bool, replyHandle: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        if canReply, let handle = replyHandle {
            content.categoryIdentifier = "REPLY_CATEGORY"
            content.userInfo = ["replyHandle": handle]
        }

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

    // Handle user interaction, including text replies
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                didReceive response: UNNotificationResponse, 
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "REPLY_ACTION",
           let textResponse = response as? UNTextInputNotificationResponse {
            let replyText = textResponse.userText
            let userInfo = response.notification.request.content.userInfo
            if let replyHandle = userInfo["replyHandle"] as? String {
                // Forward back to Dart
                methodChannel?.invokeMethod("sendReply", arguments: [
                    "replyHandle": replyHandle,
                    "text": replyText
                ])
            }
        }
        completionHandler()
    }
}
