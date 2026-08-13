package com.connecto.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val prefs = context.getSharedPreferences("pakku_prefs", Context.MODE_PRIVATE)
            val wsIp = prefs.getString("ws_ip", "")
            
            if (!wsIp.isNullOrEmpty() && !PhoneStateService.running.get()) {
                val serviceIntent = Intent(context, PhoneStateService::class.java)
                ContextCompat.startForegroundService(context, serviceIntent)
            }
        }
    }
}
