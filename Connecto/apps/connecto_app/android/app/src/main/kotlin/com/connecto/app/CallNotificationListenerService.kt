package com.connecto.app

import android.app.Notification
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class CallNotificationListenerService : NotificationListenerService() {

    private var wasDialing = false
    private var hasSentAnswered = false

    companion object {
        const val TAG = "CallNotifListener"
        const val ACTION_CALL_ANSWERED = "com.connecto.app.CALL_ANSWERED"
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
        } else if (!isCall) {
            // Phase 5.3.1 - Notification Mirroring Pipeline
            
            // 1 & 2. Verify Notification Listener Access & notification_sync_enabled
            val prefs = getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
            val syncEnabled = prefs.getBoolean("flutter_notification_sync_enabled", false)
            if (!syncEnabled) return

            // 3. Read packageName only
            // packageName is already read at the top of the method (val packageName = sbn.packageName)

            // 4. Run blocked package filtering
            val blockedPackages = setOf(
                "com.connecto.app", // Connecto itself
                "com.android.systemui", // System UI
                "android", // Android system
                "com.google.android.googlequicksearchbox"
            )

            // 5. Run sensitive package filtering
            val isSensitive = packageName.contains("authenticator", ignoreCase = true) ||
                              packageName.contains("bank", ignoreCase = true) ||
                              packageName.contains("pay", ignoreCase = true) ||
                              packageName.contains("wallet", ignoreCase = true)

            if (blockedPackages.contains(packageName) || isSensitive) {
                return
            }

            // 6. Only after passing all filters: read notification title and body
            val extras = notification.extras
            val rawTitle = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            val rawBody = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

            // 7. Validate notification (non-empty, not ongoing)
            if (rawTitle.isBlank() && rawBody.isBlank()) return
            if (sbn.isOngoing) return // ignore ongoing non-call notifications

            // Field truncation (Title: 256, Body: 512)
            val title = if (rawTitle.length > 256) rawTitle.substring(0, 256) else rawTitle
            val body = if (rawBody.length > 512) rawBody.substring(0, 512) else rawBody

            // Get app name (fallback to package name)
            val pm = applicationContext.packageManager
            val appName = try {
                val ai = pm.getApplicationInfo(packageName, 0)
                pm.getApplicationLabel(ai).toString()
            } catch (e: Exception) {
                packageName
            }

            // 8. Create JSON payload
            try {
                val payloadObj = org.json.JSONObject().apply {
                    put("type", "notification")
                    put("id", "$packageName:${sbn.id}")
                    put("package", packageName)
                    put("app", appName)
                    put("title", title)
                    put("body", body)
                    put("time", sbn.postTime)
                    put("ongoing", sbn.isOngoing)
                }

                // 9. Transmit via existing SEND_MESSAGE Intent flow
                val intent = Intent("com.connecto.app.SEND_MESSAGE").apply {
                    setPackage(this@CallNotificationListenerService.packageName)
                    putExtra("payload", payloadObj.toString())
                }
                sendBroadcast(intent)

            } catch (e: Exception) {
                Log.e(TAG, "Error processing notification payload", e)
            }
        }
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
