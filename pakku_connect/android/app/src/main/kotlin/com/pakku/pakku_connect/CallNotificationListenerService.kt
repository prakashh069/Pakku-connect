package com.pakku.pakku_connect

import android.app.Notification
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class CallNotificationListenerService : NotificationListenerService() {

    companion object {
        const val TAG = "CallNotifListener"
        const val ACTION_CALL_ANSWERED = "com.pakku.pakku_connect.CALL_ANSWERED"
        private var wasDialing = false
        private var hasSentAnswered = false
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
            
            Log.d(TAG, "Call notification detected: pkg=$packageName, title='$title', body='$body', chrono=$usesChronometer")

            val isDialing = body.contains("calling") || 
                            body.contains("ringing") || 
                            body.contains("dialing") || 
                            title.contains("calling") || 
                            title.contains("ringing") || 
                            title.contains("dialing")

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
