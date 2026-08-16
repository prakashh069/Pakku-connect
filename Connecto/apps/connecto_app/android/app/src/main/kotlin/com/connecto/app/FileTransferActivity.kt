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
        val type = intent.type

        if (Intent.ACTION_SEND == action && type != null) {
            @Suppress("DEPRECATION")
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            Log.d("FileTransfer", "[FT-ACTIVITY] uri=$uri")
            Log.d("FileTransfer", "[PHASE7] FileTransferActivity received URI")
            
            if (uri != null) {
                Log.d("FileTransfer", "[FT-ACTIVITY] starting service")
                val serviceIntent = Intent(this, FileTransferService::class.java).apply {
                    this.action = action
                    this.type = type
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startService(serviceIntent)
            }
        } else if (Intent.ACTION_SEND_MULTIPLE == action && type != null) {
            @Suppress("DEPRECATION")
            val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            
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
