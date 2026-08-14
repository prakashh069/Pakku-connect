package com.pakku.pakku_connect

import android.app.Notification
import android.content.Context
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class CallNotificationListenerService : NotificationListenerService() {

    private var wasDialing = false
    private var hasSentAnswered = false

    companion object {
        const val TAG = "CallNotifListener"
        const val ACTION_CALL_ANSWERED = "com.pakku.pakku_connect.CALL_ANSWERED"
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "NotificationListenerService connected!")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val packageName = sbn.packageName
        val notification = sbn.notification
        val category = notification.category

        val isCall = category == Notification.CATEGORY_CALL || 
                     packageName.contains("dialer") || 
                     packageName.contains("phone") || 
                     packageName.contains("incallui") ||
                     packageName.contains("telecom")

        if (isCall && sbn.isOngoing) {
            val extras = notification.extras
            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.lowercase() ?: ""
            val body = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.lowercase() ?: ""
            val usesChronometer = extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER, false)
            
            Log.d(TAG, "Call notification detected: pkg=$packageName, title='[REDACTED]', body='[REDACTED]', chrono=$usesChronometer")

            val isDialing = body.contains("calling") || 
                            body.contains("ringing") || 
                            body.contains("dialing") || 
                            body.contains("dialling") ||
                            body.contains("outgoing") ||
                            title.contains("calling") || 
                            title.contains("ringing") || 
                            title.contains("dialing") ||
                            title.contains("dialling") ||
                            title.contains("outgoing")

            if (isDialing) {
                wasDialing = true
                hasSentAnswered = false // Reset just in case
            }

            // Check if there is a timer present (either chronometer flag or actual HH:MM:SS text)
            val hasTimerText = Regex("\\d{1,2}:\\d{2}").containsMatchIn(body) || 
                               Regex("\\d{1,2}:\\d{2}").containsMatchIn(title)

            // It connected if we detect a timer, OR if it transitioned from dialing to an empty/different state
            val transitionedToConnected = wasDialing && !isDialing

            if (!hasSentAnswered && (usesChronometer || hasTimerText || transitionedToConnected)) {
                // Timer started or state transitioned -> Connected!
                Log.d(TAG, "Call connected (chrono=$usesChronometer, timerText=$hasTimerText, transition=$transitionedToConnected)! Sending ACTION_CALL_ANSWERED broadcast.")
                val intent = Intent(ACTION_CALL_ANSWERED)
                intent.setPackage(this.packageName)
                sendBroadcast(intent)
                
                hasSentAnswered = true
                wasDialing = false
            }
        } else if (!isCall && !sbn.isOngoing) {
            // General Notification Mirroring (Phase 5.3.1 + Phase 5.4)
            val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
            val syncEnabled = prefs.getBoolean("notification_sync_enabled", true)
            if (!syncEnabled) return

            // Blocked packages filtering
            if (packageName.contains("android") ||
                packageName.contains("systemui") ||
                packageName.contains("banking") ||
                packageName.contains("auth") ||
                packageName.contains("dialer") ||
                packageName.contains("phone") ||
                packageName.contains("telecom") ||
                packageName == "com.pakku.pakku_connect"
            ) {
                return
            }

            val extras = notification.extras
            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            val body = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

            if (title.isBlank() && body.isBlank()) return

            var canReply = false
            var replyHandle: String? = null
            
            // Phase 5.4: Detect RemoteInput and generate ReplyHandle
            val sessionId = prefs.getString("current_session_id", "unknown_session") ?: "unknown_session"
            
            notification.actions?.forEach { action ->
                val remoteInputs = action.remoteInputs
                if (remoteInputs != null) {
                    for (remoteInput in remoteInputs) {
                        if (remoteInput.allowFreeFormInput) {
                            canReply = true
                            replyHandle = NotificationReplyManager.storeHandle(
                                pendingIntent = action.actionIntent,
                                remoteInputKey = remoteInput.resultKey,
                                packageName = packageName,
                                sessionId = sessionId
                            )
                            break
                        }
                    }
                }
                if (canReply) return@forEach
            }

            // Dispatch payload
            val timestamp = sbn.postTime
            val payload = """
                {
                    "type": "sync.notification",
                    "version": 1,
                    "package": "$packageName",
                    "title": "${escapeJson(title)}",
                    "body": "${escapeJson(body)}",
                    "timestamp": $timestamp,
                    "canReply": $canReply,
                    "replyHandle": ${if (replyHandle != null) "\"$replyHandle\"" else "null"}
                }
            """.trimIndent()

            val intent = Intent("com.pakku.pakku_connect.SEND_MESSAGE")
            intent.setPackage(this.packageName)
            intent.putExtra("payload", payload)
            sendBroadcast(intent)
        }
    }

    private fun escapeJson(input: String): String {
        return input.replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r")
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn == null) return
        val category = sbn.notification.category
        val isCall = category == Notification.CATEGORY_CALL || 
                     sbn.packageName.contains("dialer") || 
                     sbn.packageName.contains("phone") || 
                     sbn.packageName.contains("incallui") ||
                     sbn.packageName.contains("telecom")
                     
        if (isCall) {
            wasDialing = false
            hasSentAnswered = false
        }
    }
}
