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
            val syncEnabled = prefs.getBoolean("flutter_notification_sync_enabled", true)
            if (!syncEnabled) return

            // ----------------------------------------------------------------
            // FILTERING POLICY
            // Layer 1: Hard-block system/utility packages by exact package name.
            // These are never user-facing and generate noise on macOS.
            // ----------------------------------------------------------------
            val hardBlockedPackages = setOf(
                // Connecto itself — never mirror our own service notifications
                "com.connecto.app",
                // Android system & System UI
                "android",
                "com.android.systemui",
                "com.android.settings",
                "com.android.server.telecom",
                "com.android.shell",
                // Google system services
                "com.google.android.googlequicksearchbox",
                "com.google.android.gms",
                "com.google.android.gsf",
                "com.google.android.packageinstaller",
                "com.google.android.permissioncontroller",
                // Samsung system packages (common on Samsung devices)
                "com.samsung.android.app.cocktailbarservice",
                "com.samsung.android.app.spage",
                "com.samsung.android.samsungpay",
                "com.samsung.android.incallui",
                "com.sec.android.app.launcher",
                "com.samsung.android.app.smartcapture", // screenshot
                "com.samsung.android.sm",               // device care
                // USB / MTP
                "com.android.mtp",
                // Media / download manager
                "com.android.providers.downloads"
            )

            if (hardBlockedPackages.contains(packageName)) {
                Log.d(TAG, "NOTIFICATION_BLOCKED reason=hard_blocked_package package=$packageName")
                return
            }

            // ----------------------------------------------------------------
            // Layer 2: Block by notification category.
            // These categories represent system-level events, not user messages.
            // ----------------------------------------------------------------
            val blockedCategories = setOf(
                Notification.CATEGORY_SYSTEM,               // system/device state
                Notification.CATEGORY_PROGRESS,             // downloads, long-running progress
                Notification.CATEGORY_RECOMMENDATION,       // system recommendations
                Notification.CATEGORY_STATUS,               // status bar icons (USB, etc.)
                Notification.CATEGORY_TRANSPORT,            // media transport controls
                Notification.CATEGORY_SERVICE,              // background service
                Notification.CATEGORY_WORKOUT,              // fitness sensors
                Notification.CATEGORY_LOCATION_SHARING,     // location
                Notification.CATEGORY_STOPWATCH             // stopwatch
            )

            if (category != null && blockedCategories.contains(category)) {
                Log.d(TAG, "NOTIFICATION_BLOCKED reason=blocked_category category=$category package=$packageName")
                return
            }

            // ----------------------------------------------------------------
            // Layer 3: Block by package name keyword — sensitive finance/auth apps.
            // Mirror nothing from banking, payment, or authenticator apps.
            // ----------------------------------------------------------------
            val isSensitive = packageName.contains("authenticator", ignoreCase = true) ||
                              packageName.contains("bank", ignoreCase = true) ||
                              packageName.contains(".pay", ignoreCase = true) ||
                              packageName.contains("wallet", ignoreCase = true) ||
                              packageName.contains("mtp", ignoreCase = true)

            if (isSensitive) {
                Log.d(TAG, "NOTIFICATION_BLOCKED reason=sensitive_package package=$packageName")
                return
            }

            // ----------------------------------------------------------------
            // Layer 4: Block by title/body keyword — screenshot & screen recording.
            // These are posted by SystemUI and slip through the package filter
            // on some manufacturer skins.
            // Only read extras here, after all cheaper checks have passed.
            // ----------------------------------------------------------------
            val extras = notification.extras
            val rawTitle = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            val rawBody  = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()  ?: ""

            val titleLower = rawTitle.lowercase()
            val bodyLower  = rawBody.lowercase()

            val isScreenshotNoise = titleLower.contains("screenshot") ||
                                    bodyLower.contains("screenshot")  ||
                                    titleLower.contains("screen record") ||
                                    bodyLower.contains("screen record")  ||
                                    titleLower.contains("screen capture") ||
                                    bodyLower.contains("screen capture")

            if (isScreenshotNoise) {
                Log.d(TAG, "NOTIFICATION_BLOCKED reason=screenshot_noise package=$packageName title='[REDACTED]'")
                return
            }

            // ----------------------------------------------------------------
            // All filters passed. Validate content & transmit.
            // ----------------------------------------------------------------

            // 7. Validate notification (non-empty, not ongoing)
            if (rawTitle.isBlank() && rawBody.isBlank()) return
            if (sbn.isOngoing) return // ignore ongoing non-call notifications

            // Field truncation (Title: 256, Body: 512)
            val title = if (rawTitle.length > 256) rawTitle.substring(0, 256) else rawTitle
            val body  = if (rawBody.length  > 512) rawBody.substring(0, 512)  else rawBody

            // Get app name (fallback to package name)
            val pm = applicationContext.packageManager
            val appName = try {
                val ai = pm.getApplicationInfo(packageName, 0)
                pm.getApplicationLabel(ai).toString()
            } catch (e: Exception) {
                packageName
            }

            Log.d(TAG, "NOTIFICATION_ALLOWED package=$packageName app=$appName")

            // 8. Create JSON payload
            try {
                val payloadObj = org.json.JSONObject().apply {
                    put("type", "sync.notification")
                    put("id", "$packageName:${sbn.id}")
                    put("package", packageName)
                    put("app", appName)
                    put("title", title)
                    put("body", body)
                    put("timestamp", sbn.postTime)
                    put("ongoing", sbn.isOngoing)
                }

                // 9. Transmit via existing SEND_MESSAGE Intent flow
                val intent = Intent(this@CallNotificationListenerService, PhoneStateService::class.java).apply {
                    action = "com.connecto.app.SEND_MESSAGE"
                    putExtra("payload", payloadObj.toString())
                }
                startService(intent)

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
        } else {
            val prefs = getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
            val syncEnabled = prefs.getBoolean("flutter_notification_sync_enabled", true)
            if (syncEnabled) {
                try {
                    val payloadObj = org.json.JSONObject().apply {
                        put("type", "sync.notification.removed")
                        put("id", "${sbn.packageName}:${sbn.id}")
                    }
                    val intent = Intent(this@CallNotificationListenerService, PhoneStateService::class.java).apply {
                        action = "com.connecto.app.SEND_MESSAGE"
                        putExtra("payload", payloadObj.toString())
                    }
                    startService(intent)
                } catch (e: Exception) {
                    Log.e(TAG, "Error processing notification removed payload", e)
                }
            }
        }
    }
}
