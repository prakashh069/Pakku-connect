package com.connecto.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import org.json.JSONObject

class FileTransferTransport(private val context: Context) {
    
    private var messageListener: ((JSONObject) -> Unit)? = null

    private val wsMessageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val token = intent.getStringExtra("secure_token")
            if (token != "INTERNAL_FT_SECURE_TOKEN") {
                android.util.Log.w("FileTransfer", "[FT_TRANSPORT] Dropped spoofed broadcast")
                return
            }

            val payload = intent.getStringExtra("payload")
            if (payload != null) {
                android.util.Log.d("FileTransfer", "[FT_BROADCAST_RECEIVED] payload=$payload")
                try {
                    val json = JSONObject(payload)
                    val type = json.optString("type")
                    if (type.startsWith("file.transfer.")) {
                        messageListener?.invoke(json)
                    }
                } catch (e: Exception) {
                    // Ignore malformed JSON
                }
            }
        }
    }

    fun startListening(listener: (JSONObject) -> Unit) {
        messageListener = listener
        val filter = IntentFilter("com.connecto.app.FT_MESSAGE")
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(wsMessageReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(wsMessageReceiver, filter)
        }
    }

    fun stopListening() {
        try {
            context.unregisterReceiver(wsMessageReceiver)
        } catch (e: Exception) {
            // Ignore if not registered
        }
        messageListener = null
    }

    fun send(message: JSONObject) {
        android.util.Log.d(
            "FileTransfer",
            "[FT-TRANSPORT] outgoing:\n${message.toString(2)}"
        )
        val intent = Intent(context, PhoneStateService::class.java).apply {
            action = "com.connecto.app.SEND_MESSAGE"
            putExtra("payload", message.toString())
        }
        context.startService(intent)
    }

    fun sendChunkReference(transferId: String, chunkIndex: Int, totalChunks: Int, chunkPath: String) {
        val intent = Intent(context, PhoneStateService::class.java).apply {
            action = "com.connecto.app.SEND_FILE_CHUNK"
            putExtra("transferId", transferId)
            putExtra("chunkIndex", chunkIndex)
            putExtra("totalChunks", totalChunks)
            putExtra("chunkPath", chunkPath)
        }
        context.startService(intent)
    }
}
