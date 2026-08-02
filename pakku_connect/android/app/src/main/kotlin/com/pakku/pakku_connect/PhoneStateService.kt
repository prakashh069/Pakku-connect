package com.pakku.pakku_connect

import android.app.*
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import okhttp3.*
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

class PhoneStateService : Service() {
    private var httpClient: OkHttpClient? = null
    private var webSocket: WebSocket? = null
    private var telephonyManager: TelephonyManager? = null

    // Legacy path (SDK < 31)
    private var legacyListener: PhoneStateListener? = null

    // Modern path (SDK 31+)
    private var telephonyCallback: TelephonyCallback? = null

    private var lastState = TelephonyManager.CALL_STATE_IDLE
    private var missedCallNotificationId = 100

    private val mainHandler = Handler(Looper.getMainLooper())
    private var isListenersStarted = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Pakku Connect")
            .setContentText("Listening for calls")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        startForeground(1, notification)

        startWebSocket()
        startPhoneListener()
        
        // START_STICKY ensures if the OS kills this service to reclaim memory,
        // it will be automatically restarted with a null intent when memory frees up.
        // This is critical since phone calls are unpredictable and the service must be running.
        return START_STICKY
    }

    // ---------------------------------------------------------------
    // TLS trust — dev vs prod. See docs/02_TDD.md §6 and ADR-004.
    // ---------------------------------------------------------------

    private fun buildDevTrustAllClient(): OkHttpClient {
        val trustAllCerts = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })
        val sslContext = SSLContext.getInstance("TLS").apply {
            init(null, trustAllCerts, SecureRandom())
        }
        return OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .pingInterval(15, TimeUnit.SECONDS)
            .sslSocketFactory(sslContext.socketFactory, trustAllCerts[0] as X509TrustManager)
            .hostnameVerifier { _, _ -> true }
            .build()
    }

    private fun buildProdPinnedClient(pinnedFingerprint: String): OkHttpClient {
        val pinningTrustManager = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                val cert = chain?.firstOrNull()
                    ?: throw CertificateException("No certificate presented")
                val digest = MessageDigest.getInstance("SHA-256").digest(cert.encoded)
                val hex = digest.joinToString("") { "%02x".format(it) }
                if (!hex.equals(pinnedFingerprint, ignoreCase = true)) {
                    throw CertificateException(
                        "Certificate fingerprint mismatch — refusing connection " +
                        "(expected=$pinnedFingerprint actual=$hex)")
                }
            }
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        }
        val sslContext = SSLContext.getInstance("TLS").apply {
            init(null, arrayOf(pinningTrustManager), SecureRandom())
        }
        return OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .pingInterval(15, TimeUnit.SECONDS)
            .sslSocketFactory(sslContext.socketFactory, pinningTrustManager)
            .hostnameVerifier { _, _ -> true }
            .build()
    }

    private fun getOkHttpClient(pinnedFingerprint: String?): OkHttpClient {
        httpClient?.let { return it }

        val client = if (!pinnedFingerprint.isNullOrEmpty()) {
            buildProdPinnedClient(pinnedFingerprint)
        } else if (BuildConfig.DEBUG) {
            Log.w(TAG, "No cert_fp available — falling back to DEV trust-all client.")
            buildDevTrustAllClient()
        } else {
            Log.e(TAG, "No cert_fp available and this is a release build.")
            throw IllegalStateException("Missing cert_fp in production build")
        }
        
        httpClient = client
        return client
    }

    // ---------------------------------------------------------------
    // WebSocket lifecycle
    // ---------------------------------------------------------------

    private val reconnectRunnable = Runnable { startWebSocket() }

    private fun stopWebSocket() {
        // Enforce exactly one reconnect timer
        mainHandler.removeCallbacks(reconnectRunnable)
        
        // Enforce exactly one WebSocket connection
        webSocket?.cancel()
        webSocket = null
    }

    private fun scheduleReconnect() {
        // Remove any existing reconnect task before scheduling another
        mainHandler.removeCallbacks(reconnectRunnable)
        mainHandler.postDelayed(reconnectRunnable, 5000)
    }

    private fun startWebSocket() {
        stopWebSocket()

        val prefs = getSharedPreferences("pakku_prefs", Context.MODE_PRIVATE)
        val ip = prefs.getString("ws_ip", "") ?: ""
        val port = prefs.getInt("ws_port", 0)
        val certFp = prefs.getString("cert_fp", "") ?: ""

        // Validate configuration thoroughly before proceeding
        if (ip.isEmpty() || port !in 1..65535) {
            Log.e(TAG, "Invalid WebSocket configuration: ip=$ip, port=$port")
            return
        }
        if (certFp.isNotEmpty() && !certFp.matches(Regex("^[0-9a-fA-F]{64}$"))) {
            Log.e(TAG, "Invalid certificate fingerprint format: $certFp")
            return
        }

        val url = "wss://$ip:$port"

        val client = try {
            getOkHttpClient(certFp)
        } catch (e: IllegalStateException) {
            Log.e(TAG, "Cannot start WebSocket: ${e.message}")
            return
        }

        val request = Request.Builder().url(url).build()
        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "WSS connected")
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "WSS failure: ${t.message}")
                scheduleReconnect()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "WSS closed: $code $reason")
                if (code != 1000) {
                    scheduleReconnect()
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val json = JSONObject(text)
                    when (json.optString("type")) {
                        "answer_call" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                try {
                                    val tm = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                                    tm.acceptRingingCall()
                                    Log.d(TAG, "Native answer executed")
                                } catch (e: SecurityException) {
                                    Log.e(TAG, "Permission denied for acceptRingingCall", e)
                                }
                            } else {
                                Log.w(TAG, "acceptRingingCall requires API 28+")
                            }
                        }
                        "reject_call" -> {
                            try {
                                val tm = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                    tm.endCall()
                                } else {
                                    @Suppress("DEPRECATION")
                                    tm.silenceRinger()
                                }
                                Log.d(TAG, "Native reject executed")
                            } catch (e: SecurityException) {
                                Log.e(TAG, "Permission denied for reject_call", e)
                            }
                        }
                        "dial" -> {
                            val number = json.optString("number")
                            if (number.isNotEmpty()) {
                                try {
                                    val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$number"))
                                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    startActivity(intent)
                                    Log.d(TAG, "Native dial executed")
                                } catch (e: SecurityException) {
                                    Log.e(TAG, "Permission denied for dial", e)
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to parse/handle control message: ${e.message}")
                }
            }
        })
    }

    // ---------------------------------------------------------------
    // Telephony state — API-level branching. See docs/02_TDD.md §5.
    // ---------------------------------------------------------------

    private fun startPhoneListener() {
        if (isListenersStarted) return
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val executor = ContextCompat.getMainExecutor(this)
                val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) {
                        handleStateChange(state, null)
                    }
                }
                telephonyCallback = callback
                telephonyManager?.registerTelephonyCallback(executor, callback)
            } else {
                @Suppress("DEPRECATION")
                val listener = object : PhoneStateListener() {
                    @Suppress("DEPRECATION")
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                        handleStateChange(state, phoneNumber)
                    }
                }
                legacyListener = listener
                @Suppress("DEPRECATION")
                telephonyManager?.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
            }
            isListenersStarted = true
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission denied for TelephonyCallback/PhoneStateListener", e)
            // Note: Degrades gracefully; the service won't crash, but it won't emit telephony updates.
        }
    }

    /** Shared by both the legacy and modern telephony callback paths. */
    private fun handleStateChange(state: Int, phoneNumber: String?) {
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                val number = phoneNumber ?: "Unknown"
                val msg = """{"type":"incoming_call","phoneNumber":"$number","contactName":""}"""
                webSocket?.send(msg)
                Log.d(TAG, "Sent incoming_call ($number)")
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                if (lastState == TelephonyManager.CALL_STATE_RINGING) {
                    webSocket?.send("""{"type":"call_state","state":"answered"}""")
                    Log.d(TAG, "Sent call_state=answered")
                }
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                if (lastState == TelephonyManager.CALL_STATE_RINGING ||
                    lastState == TelephonyManager.CALL_STATE_OFFHOOK
                ) {
                    webSocket?.send("""{"type":"call_state","state":"ended"}""")
                    Log.d(TAG, "Sent call_state=ended")
                }
                // Missed call: went straight from RINGING to IDLE, never OFFHOOK.
                if (lastState == TelephonyManager.CALL_STATE_RINGING) {
                    showMissedCallNotification(phoneNumber ?: "Unknown")
                }
            }
        }
        lastState = state
    }

    private fun showMissedCallNotification(phoneNumber: String) {
        val manager = getSystemService(NotificationManager::class.java)
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Missed Call")
            .setContentText(phoneNumber)
            .setSmallIcon(android.R.drawable.stat_notify_missed_call)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        manager.notify(missedCallNotificationId++, notification)
    }

    override fun onDestroy() {
        // Enforce invariants during teardown
        stopWebSocket()
        
        // Explicitly clean up singleton OkHttpClient
        httpClient?.let {
            it.dispatcher.cancelAll()
            it.dispatcher.executorService.shutdown()
            it.connectionPool.evictAll()
        }
        httpClient = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            telephonyCallback?.let { telephonyManager?.unregisterTelephonyCallback(it) }
        } else {
            @Suppress("DEPRECATION")
            legacyListener?.let { telephonyManager?.listen(it, PhoneStateListener.LISTEN_NONE) }
        }
        telephonyCallback = null
        legacyListener = null
        isListenersStarted = false

        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Call Service", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    companion object {
        private const val TAG = "PhoneStateService"
        private const val CHANNEL_ID = "pakku_call_service"
    }
}
