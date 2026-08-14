package com.connecto.app

import android.app.Service
import android.content.Intent
import android.net.Uri
import android.os.IBinder
import android.util.Base64
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.security.MessageDigest

class ShareService : Service() {
    private val TAG = "ShareService"
    private val serviceScope = CoroutineScope(Dispatchers.IO)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val action = intent.action
        val type = intent.type

        if (Intent.ACTION_SEND == action && type != null) {
            serviceScope.launch {
                try {
                    handleSend(intent, type)
                } catch (e: Exception) {
                    Log.e(TAG, "Error handling share intent", e)
                } finally {
                    stopSelf(startId)
                }
            }
        } else {
            stopSelf(startId)
        }

        return START_NOT_STICKY
    }

    private fun handleSend(intent: Intent, type: String) {
        if (type == "text/plain") {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
            sendPayload(createPayload(
                mime = "text/plain",
                content = text,
                size = text.toByteArray(Charsets.UTF_8).size,
                sha256 = null
            ))
        } else if (type.startsWith("image/")) {
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return
            processImage(uri, type)
        } else {
            Log.w(TAG, "Unsupported share type: $type")
        }
    }

    private fun processImage(uri: Uri, type: String) {
        // Enforce Phase 6 constraints (jpeg/png only)
        val normalizedMime = if (type == "image/png" || type == "image/jpeg") type else "image/jpeg"
        
        val imageBytes = ImageCompressor.compressAndStripExif(this, uri) ?: return
        val base64Content = Base64.encodeToString(imageBytes, Base64.NO_WRAP)
        
        val md = MessageDigest.getInstance("SHA-256")
        val hashBytes = md.digest(imageBytes)
        val sha256 = hashBytes.joinToString("") { "%02x".format(it) }

        sendPayload(createPayload(
            mime = normalizedMime,
            content = base64Content,
            size = imageBytes.size,
            sha256 = sha256
        ))
    }

    private fun createPayload(mime: String, content: String, size: Int, sha256: String?): String {
        val payloadObj = JSONObject().apply {
            put("mime", mime)
            put("content", content)
            put("size", size)
            if (sha256 != null) {
                put("sha256", sha256)
            }
        }

        val envelope = JSONObject().apply {
            put("type", "share.clipboard")
            put("source", "share_sheet")
            put("version", 1)
            put("timestamp", System.currentTimeMillis())
            put("payload", payloadObj)
        }

        return envelope.toString()
    }

    private fun sendPayload(jsonString: String) {
        val intent = Intent(this, PhoneStateService::class.java).apply {
            action = "com.connecto.app.SEND_MESSAGE"
            putExtra("payload", jsonString)
        }
        startService(intent)
        Log.d(TAG, "Shared payload forwarded to WebSocket transport")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
