package com.pakku.pakku_connect

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import android.util.Log

class ClipboardReaderActivity : Activity() {
    companion object {
        const val ACTION_READ_CLIPBOARD = "com.pakku.pakku_connect.ACTION_READ_CLIPBOARD"
        const val ACTION_SEND_TO_MAC = "com.pakku.pakku_connect.ACTION_SEND_TO_MAC"
    }

    private var hasProcessed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        if (intent.action == Intent.ACTION_SEND) {
            // Triggered from Share menu - no need to wait for focus
            var textToSend: String? = null
            if ("text/plain" == intent.type) {
                textToSend = intent.getStringExtra(Intent.EXTRA_TEXT)
            }
            sendAndFinish(textToSend)
        }
        // If it's ACTION_READ_CLIPBOARD, we wait for onWindowFocusChanged
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && !hasProcessed && intent.action == ACTION_READ_CLIPBOARD) {
            hasProcessed = true
            var textToSend: String? = null
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            
            // Log for debugging
            Log.d("ClipboardReader", "hasPrimaryClip: ${clipboard.hasPrimaryClip()}")
            
            if (clipboard.hasPrimaryClip() && clipboard.primaryClip != null) {
                val item = clipboard.primaryClip!!.getItemAt(0)
                textToSend = item.text?.toString()
            }
            sendAndFinish(textToSend)
        }
    }

    private fun sendAndFinish(textToSend: String?) {
        if (textToSend != null && textToSend.isNotEmpty()) {
            val broadcastIntent = Intent(ACTION_SEND_TO_MAC)
            broadcastIntent.putExtra("text", textToSend)
            broadcastIntent.setPackage(packageName)
            sendBroadcast(broadcastIntent)
            Toast.makeText(this, "Sent to Mac", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, "No text to send", Toast.LENGTH_SHORT).show()
        }

        finish()
        overridePendingTransition(0, 0)
    }
}
