package com.connecto.app

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
        val imagePath = intent.getStringExtra("image_path")
        val deviceName = intent.getStringExtra("device_name") ?: "Mac"
        
        if (!text.isNullOrEmpty() || !imagePath.isNullOrEmpty()) {
            try {
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip: ClipData
                var snippet = ""
                
                if (!imagePath.isNullOrEmpty()) {
                    val file = java.io.File(imagePath)
                    val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                    clip = ClipData.newUri(contentResolver, "Copied from $deviceName", uri)
                    snippet = "🖼️ Image"
                } else {
                    clip = ClipData.newPlainText("Copied from $deviceName", text)
                    snippet = if (text != null && text.length > 30) text.substring(0, 27) + "..." else (text ?: "")
                }
                
                clipboard.setPrimaryClip(clip)
                // Show a brief toast
                Toast.makeText(this, "Copied from $deviceName\n$snippet", Toast.LENGTH_SHORT).show()



                // Persist it natively in case Flutter is dead and misses the broadcast
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().putString("flutter.lastReceivedClipboardText", text ?: "image").apply()
                
                // Clear the notification
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                manager.cancel(80085)
                
                // Cleanup received image file
                // Do not delete immediately as the clipboard relies on the FileProvider URI.
                // It will be cleaned up by the 1-hour rolling cache in PhoneStateService.
            } catch (e: Exception) {
                Toast.makeText(this, "Failed to copy: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
        
        // Finish immediately so the screen remains unchanged
        finish()
        overridePendingTransition(0, 0)
    }
}
