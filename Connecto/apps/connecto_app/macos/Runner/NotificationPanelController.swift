import Cocoa
import FlutterMacOS
import UserNotifications

class NotificationPanelController: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPanelController()
    private var methodChannel: FlutterMethodChannel?

    private override init() {
        super.init()
        
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        let replyAction = UNTextInputNotificationAction(identifier: "REPLY_ACTION", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Type your reply...")
        let replyCategory = UNNotificationCategory(identifier: "REPLY_CATEGORY", actions: [replyAction], intentIdentifiers: [], options: [])
        
        let copyImageAction = UNNotificationAction(identifier: "COPY_IMAGE_ACTION", title: "Copy Image", options: [])
        let openFolderAction = UNNotificationAction(identifier: "OPEN_FOLDER_ACTION", title: "Open Folder", options: [])
        let imageCategory = UNNotificationCategory(identifier: "IMAGE_RECEIVED_CATEGORY", actions: [copyImageAction, openFolderAction], intentIdentifiers: [], options: [])
        
        center.setNotificationCategories([replyCategory, imageCategory])
    }

    func setup(binaryMessenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(name: "com.connecto.app/notifications", binaryMessenger: binaryMessenger)
        
        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "showNotification":
                if let args = call.arguments as? [String: Any],
                   let title = args["title"] as? String,
                   let body = args["body"] as? String {
                    let canReply = args["canReply"] as? Bool ?? false
                    let replyHandle = args["replyHandle"] as? String
                    let filePath = args["filePath"] as? String
                    let fileName = args["fileName"] as? String
                    let mimeType = args["mimeType"] as? String
                    let isImage = args["isImage"] as? Bool ?? false
                    self?.showLocalNotification(title: title, body: body, canReply: canReply, replyHandle: replyHandle, filePath: filePath, isImage: isImage)
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing title or body", details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func showLocalNotification(title: String, body: String, canReply: Bool, replyHandle: String?, filePath: String?, isImage: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        if canReply, let handle = replyHandle {
            content.categoryIdentifier = "REPLY_CATEGORY"
            content.userInfo = ["replyHandle": handle]
        } else if isImage, let path = filePath {
            content.categoryIdentifier = "IMAGE_RECEIVED_CATEGORY"
            content.userInfo = ["filePath": path]
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[Connecto] Notification error: %@", error.localizedDescription)
            }
        }
    }
    
    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                willPresent notification: UNNotification, 
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
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
        } else if response.actionIdentifier == "COPY_IMAGE_ACTION" {
            let userInfo = response.notification.request.content.userInfo
            if let filePath = userInfo["filePath"] as? String {
                if let image = NSImage(contentsOfFile: filePath) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
            }
        } else if response.actionIdentifier == "OPEN_FOLDER_ACTION" {
            let userInfo = response.notification.request.content.userInfo
            if let filePath = userInfo["filePath"] as? String {
                NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
            }
        }
        completionHandler()
    }
}
