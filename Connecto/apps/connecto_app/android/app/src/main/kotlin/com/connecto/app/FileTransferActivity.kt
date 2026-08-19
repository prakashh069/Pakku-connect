package com.connecto.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

import android.util.Log
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
class FileTransferActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        Log.d("FileTransfer", "[PHASE7] ACTIVITY CREATED")
        Log.d("FileTransfer", "[PHASE7] INTENT ACTION: ${intent.action}")
        Log.d("FileTransfer", "[PHASE7] INTENT TYPE: ${intent.type}")
        val extraMimeTypes = intent.getStringArrayExtra(Intent.EXTRA_MIME_TYPES)?.joinToString(", ")
        Log.d("FileTransfer", "[PHASE7] EXTRA MIME TYPE: $extraMimeTypes")

        val intent = intent
        val action = intent.action
        var type = intent.type ?: "application/octet-stream"

        if (Intent.ACTION_SEND == action) {
            @Suppress("DEPRECATION")
            var uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            
            if (uri == null && intent.clipData != null && intent.clipData!!.itemCount > 0) {
                uri = intent.clipData!!.getItemAt(0).uri
            }
            
            if (uri == null && intent.hasExtra(Intent.EXTRA_TEXT)) {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (text != null) {
                    try {
                        val tempFile = java.io.File(cacheDir, "Shared_Text_${System.currentTimeMillis()}.txt")
                        tempFile.writeText(text)
                        uri = Uri.fromFile(tempFile)
                        type = "text/plain"
                    } catch (e: Exception) {
                        Log.e("FileTransfer", "Failed to write text", e)
                    }
                }
            }
            
            Log.d("FileTransfer", "[FT-ACTIVITY] uri=$uri")
            Log.d("FileTransfer", "[PHASE7] FileTransferActivity received URI")
            
            if (uri != null) {
                Log.d("FileTransfer", "[FT-ACTIVITY] starting service")
                val serviceIntent = Intent(this, FileTransferService::class.java).apply {
                    this.action = action
                    this.type = type
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = android.content.ClipData.newRawUri("", uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startService(serviceIntent)
            } else {
                android.widget.Toast.makeText(this, "Connecto: No file or text found to share", android.widget.Toast.LENGTH_LONG).show()
            }
        } else if (Intent.ACTION_SEND_MULTIPLE == action && type != null) {
            @Suppress("DEPRECATION")
            val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)

            // --- [SHARE_RECEIVED] Debug Log ---
            val fileNames = uris?.mapNotNull { uri ->
                try { contentResolver.query(uri, null, null, null, null)?.use { c ->
                    if (c.moveToFirst()) c.getString(c.getColumnIndexOrThrow(android.provider.OpenableColumns.DISPLAY_NAME)) else null
                }} catch (e: Exception) { uri.lastPathSegment }
            }
            Log.d("ConnectoShare", "[SHARE_RECEIVED] action=ACTION_SEND_MULTIPLE type=$type")
            Log.d("ConnectoShare", "[SHARE_RECEIVED] file_count=${uris?.size ?: 0}")
            Log.d("ConnectoShare", "[SHARE_RECEIVED] file_names=${fileNames?.joinToString(", ")}")
            // ----------------------------------

            Log.d("FileTransfer", "[PHASE8] SEND MULTIPLE RECEIVED")
            Log.d("FileTransfer", "[PHASE8] IMAGE COUNT: ${uris?.size}")

            if (uris != null && uris.isNotEmpty()) {
                Log.d("FileTransfer", "[PHASE8] ZIP CREATION START")
                TransferQueueManager.startQueue(this, uris, type)
                Log.d("FileTransfer", "[PHASE8] ZIP CREATION COMPLETE (Async triggered)")
                Log.d("FileTransfer", "[PHASE8] SERVICE STARTED (Async triggered)")
            }
        }
        
        finish() // Exit immediately
    }
}
