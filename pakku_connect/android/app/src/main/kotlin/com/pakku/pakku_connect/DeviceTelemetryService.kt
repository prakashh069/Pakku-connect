package com.pakku.pakku_connect

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.BatteryManager
import android.os.IBinder
import android.util.Log
import org.json.JSONObject

class DeviceTelemetryService : Service() {

    private var lastBatteryPercentage = -1
    private var lastChargingState: Boolean? = null
    private var lastNetworkType = "unknown"
    private var lastTelemetryTime = 0L

    private var batteryReceiver: BroadcastReceiver? = null
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    companion object {
        private const val TAG = "DeviceTelemetryService"
        const val ACTION_TELEMETRY_BRIDGE = "com.pakku.pakku_connect.TELEMETRY_BRIDGE"
        const val EXTRA_TELEMETRY_JSON = "telemetry_json"
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "DeviceTelemetryService created")
        setupBatteryReceiver()
        setupNetworkMonitoring()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.i(TAG, "DeviceTelemetryService destroyed")
        batteryReceiver?.let { unregisterReceiver(it) }
        batteryReceiver = null
        
        networkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        networkCallback = null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "DeviceTelemetryService started")
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun setupBatteryReceiver() {
        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == Intent.ACTION_BATTERY_CHANGED) {
                    processBatteryIntent(intent)
                }
            }
        }
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        registerReceiver(batteryReceiver, filter)
    }

    private fun setupNetworkMonitoring() {
        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        
        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                super.onCapabilitiesChanged(network, networkCapabilities)
                val newNetworkType = when {
                    networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                    networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                    networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                    else -> "unknown"
                }
                if (newNetworkType != lastNetworkType) {
                    lastNetworkType = newNetworkType
                    evaluateAndSendTelemetry(forceSend = true)
                }
            }

            override fun onLost(network: Network) {
                super.onLost(network)
                lastNetworkType = "none"
                evaluateAndSendTelemetry(forceSend = true)
            }
        }
        
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
            
        connectivityManager?.registerNetworkCallback(request, networkCallback!!)
        
        // Initial state
        val activeNetwork = connectivityManager?.activeNetwork
        val capabilities = connectivityManager?.getNetworkCapabilities(activeNetwork)
        if (capabilities != null) {
            lastNetworkType = when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                else -> "unknown"
            }
        } else {
            lastNetworkType = "none"
        }
    }

    private fun processBatteryIntent(intent: Intent) {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)

        val percentage = if (level >= 0 && scale > 0) (level * 100f / scale).toInt() else -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || plugged > 0

        var forceSend = false
        if (lastChargingState != isCharging) {
            forceSend = true // Always send if charging state changes
        }

        lastBatteryPercentage = percentage
        lastChargingState = isCharging

        evaluateAndSendTelemetry(forceSend)
    }

    private fun evaluateAndSendTelemetry(forceSend: Boolean) {
        val now = System.currentTimeMillis()
        val timeSinceLast = now - lastTelemetryTime

        // Throttling rules:
        // 1. Force send (charging flipped or network changed) - max 1 per second
        // 2. Battery changed - max 1 per 30 seconds
        val shouldSend = if (forceSend) {
            timeSinceLast >= 1000 // 1 sec throttle for force sends
        } else {
            timeSinceLast >= 30000 // 30 sec throttle for general battery updates
        }

        if (shouldSend) {
            sendTelemetryBroadcast()
            lastTelemetryTime = now
        }
    }

    private fun sendTelemetryBroadcast() {
        try {
            val batteryObj = JSONObject().apply {
                put("percentage", lastBatteryPercentage)
                put("charging", lastChargingState ?: false)
            }

            val telemetryJson = JSONObject().apply {
                put("type", "device.telemetry")
                put("version", 1)
                put("battery", batteryObj)
                put("network", lastNetworkType)
            }

            val intent = Intent(ACTION_TELEMETRY_BRIDGE)
            intent.putExtra(EXTRA_TELEMETRY_JSON, telemetryJson.toString())
            sendBroadcast(intent)
            
            Log.d(TAG, "Sent telemetry bridge broadcast")
        } catch (e: Exception) {
            Log.e(TAG, "Error building telemetry JSON", e)
        }
    }
}
