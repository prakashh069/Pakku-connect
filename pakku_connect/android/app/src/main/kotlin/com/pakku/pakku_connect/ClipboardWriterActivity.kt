package com.pakku.pakku_connect

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.widget.Toast

class ClipboardWriterActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val text = intent.getStringExtra("clipboard_text")
        val deviceName = intent.getStringExtra("device_name") ?: "Mac"
        if (!text.isNullOrEmpty()) {
            try {
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip = ClipData.newPlainText("Copied from $deviceName", text)
                clipboard.setPrimaryClip(clip)
                // Show a brief toast
                val snippet = if (text.length > 30) text.substring(0, 27) + "..." else text
                Toast.makeText(this, "Copied from $deviceName\n$snippet", Toast.LENGTH_SHORT).show()

                // Forward to Flutter so ClipboardSyncManager can track _lastReceivedText for deduplication
                val broadcastIntent = android.content.Intent("com.pakku.pakku_connect.WS_MESSAGE")
                broadcastIntent.setPackage(packageName)
                val jsonPayload = org.json.JSONObject()
                jsonPayload.put("type", "share.clipboard")
                jsonPayload.put("schemaVersion", 1)
                val innerPayload = org.json.JSONObject()
                innerPayload.put("text", text)
                innerPayload.put("deviceName", deviceName)
                jsonPayload.put("payload", innerPayload)
                broadcastIntent.putExtra("payload", jsonPayload.toString())
                sendBroadcast(broadcastIntent)

                // Persist it natively in case Flutter is dead and misses the broadcast
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().putString("flutter.lastReceivedClipboardText", text).apply()
                
                // Clear the notification
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                manager.cancel(80085)
            } catch (e: Exception) {
                Toast.makeText(this, "Failed to copy: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
        
        // Finish immediately so the screen remains unchanged
        finish()
        overridePendingTransition(0, 0)
    }
}
