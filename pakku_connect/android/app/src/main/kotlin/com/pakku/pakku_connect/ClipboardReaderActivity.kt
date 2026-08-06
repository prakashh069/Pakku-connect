package com.pakku.pakku_connect

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import android.util.Log
import android.net.Uri
import android.os.Parcelable
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

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
            var imageUri: Uri? = null

            if ("text/plain" == intent.type) {
                textToSend = intent.getStringExtra(Intent.EXTRA_TEXT)
            } else if (intent.type?.startsWith("image/") == true) {
                imageUri = intent.getParcelableExtra<Parcelable>(Intent.EXTRA_STREAM) as? Uri
            }

            processAndSend(textToSend, imageUri)
        }
        // If it's ACTION_READ_CLIPBOARD, we wait for onWindowFocusChanged
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && !hasProcessed && intent.action == ACTION_READ_CLIPBOARD) {
            hasProcessed = true
            var textToSend: String? = null
            var imageUri: Uri? = null
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            
            Log.d("ClipboardReader", "hasPrimaryClip: ${clipboard.hasPrimaryClip()}")
            
            if (clipboard.hasPrimaryClip() && clipboard.primaryClip != null) {
                val item = clipboard.primaryClip!!.getItemAt(0)
                if (item.uri != null) {
                    imageUri = item.uri
                } else {
                    textToSend = item.text?.toString()
                }
            }
            processAndSend(textToSend, imageUri)
        }
    }

    private fun processAndSend(textToSend: String?, imageUri: Uri?) {
        var savedImagePath: String? = null
        if (imageUri != null) {
            try {
                val inputStream: InputStream? = contentResolver.openInputStream(imageUri)
                val cacheFile = File(cacheDir, "shared_image.tmp")
                val outputStream = FileOutputStream(cacheFile)
                inputStream?.copyTo(outputStream)
                inputStream?.close()
                outputStream.close()
                savedImagePath = cacheFile.absolutePath
            } catch (e: Exception) {
                Log.e("ClipboardReader", "Failed to read image", e)
            }
        }

        if ((textToSend != null && textToSend.isNotEmpty()) || savedImagePath != null) {
            val broadcastIntent = Intent(ACTION_SEND_TO_MAC)
            if (textToSend != null) {
                broadcastIntent.putExtra("text", textToSend)
            }
            if (savedImagePath != null) {
                broadcastIntent.putExtra("imagePath", savedImagePath)
            }
            broadcastIntent.setPackage(packageName)
            sendBroadcast(broadcastIntent)
            Toast.makeText(this, "Sent to Mac", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, "Nothing to send", Toast.LENGTH_SHORT).show()
        }

        finish()
        overridePendingTransition(0, 0)
    }
}
