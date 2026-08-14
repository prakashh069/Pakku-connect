package com.connecto.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

class ShareTargetActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val intent = intent
        val action = intent.action
        val type = intent.type

        if (Intent.ACTION_SEND == action && type != null) {
            val serviceIntent = Intent(this, ShareService::class.java).apply {
                this.action = action
                this.type = type
                
                if (type == "text/plain") {
                    intent.getStringExtra(Intent.EXTRA_TEXT)?.let {
                        putExtra(Intent.EXTRA_TEXT, it)
                    }
                } else if (type.startsWith("image/")) {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let {
                        putExtra(Intent.EXTRA_STREAM, it)
                    }
                }
            }
            startService(serviceIntent)
        }
        
        finish() // Exit immediately
    }
}
