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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        var textToSend: String? = null

        when (intent.action) {
            Intent.ACTION_SEND -> {
                // Triggered from Share menu
                if ("text/plain" == intent.type) {
                    textToSend = intent.getStringExtra(Intent.EXTRA_TEXT)
                }
            }
            ACTION_READ_CLIPBOARD -> {
                // Triggered from notification action
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                if (clipboard.hasPrimaryClip() && clipboard.primaryClip != null) {
                    val item = clipboard.primaryClip!!.getItemAt(0)
                    textToSend = item.text?.toString()
                }
            }
        }

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
