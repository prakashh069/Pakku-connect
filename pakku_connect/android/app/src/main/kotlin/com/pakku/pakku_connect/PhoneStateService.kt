package com.pakku.pakku_connect

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.telecom.TelecomManager
import android.provider.ContactsContract
import android.telephony.TelephonyManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import okhttp3.*
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

class PhoneStateService : Service() {
    private var httpClient: OkHttpClient? = null
    private var webSocket: WebSocket? = null
    private val socketLock = Any()
    @Volatile
    private var authenticated = false
    private var telephonyManager: TelephonyManager? = null

    private var callStateReceiver: android.content.BroadcastReceiver? = null
    private var notificationReceiver: android.content.BroadcastReceiver? = null

    private var lastState = TelephonyManager.CALL_STATE_IDLE
    private var missedCallNotificationId = 100

    private val mainHandler = Handler(Looper.getMainLooper())
    private var isListenersStarted = false

    private var reconnectAttempt = 0
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onCreate() {
        super.onCreate()
        running.set(true)
        createNotificationChannel()
        startNetworkMonitoring()
    }

    private fun startNetworkMonitoring() {
        if (networkCallback != null) return
        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.d(TAG, "Network available, triggering immediate reconnect")
                synchronized(socketLock) {
                    mainHandler.removeCallbacks(reconnectRunnable)
                    mainHandler.post { startWebSocket() }
                }
            }
        }
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
            
        connectivityManager.registerNetworkCallback(request, callback)
        networkCallback = callback
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "com.pakku.pakku_connect.UNPAIR") {
            try {
                val json = JSONObject().apply { put("type", "unpair") }
                sendAuthenticated(json.toString())
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send unpair message", e)
            }
            val prefs = getSharedPreferences("pakku_prefs", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("paired", false).apply()
            
            val broadcastIntent = Intent("com.pakku.pakku_connect.UNPAIRED")
            broadcastIntent.setPackage(packageName)
            sendBroadcast(broadcastIntent)
            
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                stopSelf()
            }, 500)
            return START_NOT_STICKY
        }

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
            .pingInterval(30, TimeUnit.SECONDS)
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
            .pingInterval(30, TimeUnit.SECONDS)
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
        synchronized(socketLock) {
            authenticated = false
            mainHandler.removeCallbacks(reconnectRunnable)
            webSocket?.cancel()
            webSocket = null
        }
    }

    private fun scheduleReconnect() {
        // Remove any existing reconnect task before scheduling another
        mainHandler.removeCallbacks(reconnectRunnable)
        val maxDelay = 30000L
        val delay = if (reconnectAttempt < 5) (1L shl reconnectAttempt) * 1000L else maxDelay
        reconnectAttempt++
        
        Log.d(TAG, "Scheduling reconnect in ${delay}ms")
        mainHandler.postDelayed(reconnectRunnable, delay)
    }

    private fun startWebSocket() {
        synchronized(socketLock) {
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
            Log.d(TAG, "WebSocket CONNECT")
            webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                synchronized(socketLock) {
                    if (this@PhoneStateService.webSocket !== webSocket) {
                        Log.d(TAG, "Stale socket onOpen, cancelling")
                        webSocket.cancel()
                        return
                    }
                    
                    Log.d(TAG, "WebSocket OPEN")
                    reconnectAttempt = 0
                    try {
                        val helloMsg = JSONObject().apply {
                            put("type", "hello")
                            put("deviceName", android.os.Build.MODEL)
                            put("platform", "android_service")
                        }
                        Log.d(TAG, "SEND hello")
                        webSocket.send(helloMsg.toString())

                        authenticated = true

                        val msg = JSONObject().apply {
                            put("type", "device_state")
                            put("state", "connected")
                        }
                        Log.d(TAG, "SEND device_state")
                        webSocket.send(msg.toString())
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to send initial messages: ${e.message}")
                    }
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                synchronized(socketLock) {
                    if (this@PhoneStateService.webSocket !== webSocket) return
                    Log.e(TAG, "WSS failure: ${t.message}")
                    authenticated = false
                    scheduleReconnect()
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                synchronized(socketLock) {
                    if (this@PhoneStateService.webSocket !== webSocket) {
                        webSocket.cancel()
                        return
                    }
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                synchronized(socketLock) {
                    if (this@PhoneStateService.webSocket !== webSocket) return
                    Log.d(TAG, "WSS closed: $code $reason")
                    if (code != 1000) {
                        authenticated = false
                        scheduleReconnect()
                    }
                }
            }

            override fun onMessage(webSocket: WebSocket, bytes: okio.ByteString) {
                onMessage(webSocket, bytes.utf8())
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                synchronized(socketLock) {
                    if (this@PhoneStateService.webSocket !== webSocket) return
                }
                try {
                    val json = JSONObject(text)
                    val msgType = json.optString("type")
                    when (msgType) {
                        "unpair" -> {
                            Log.i(TAG, "Received unpair command")
                            val prefs = getSharedPreferences("pakku_prefs", Context.MODE_PRIVATE)
                            prefs.edit().putBoolean("paired", false).apply()
                            val broadcastIntent = Intent("com.pakku.pakku_connect.UNPAIRED")
                            broadcastIntent.setPackage(packageName)
                            sendBroadcast(broadcastIntent)
                            stopSelf()
                        }
                        "contacts_request" -> {
                            syncContacts()
                        }
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
                                    Log.d(TAG, "Native reject executed")
                                } else {
                                    @Suppress("DEPRECATION")
                                    tm.silenceRinger()
                                    Log.d(TAG, "Native silenceRinger executed (legacy)")
                                }
                            } catch (e: SecurityException) {
                                Log.e(TAG, "Permission denied for reject_call", e)
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed to reject call", e)
                            }
                        }
                        "end_call" -> {
                            handleEndCall(webSocket)
                        }
                        "dial" -> {
                            val number = json.optString("number")
                            if (number.isNotEmpty()) {
                                try {
                                    val tm = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                                    if (ContextCompat.checkSelfPermission(this@PhoneStateService, android.Manifest.permission.CALL_PHONE) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                        tm.placeCall(Uri.parse("tel:$number"), android.os.Bundle())
                                        Log.d(TAG, "Native dial executed")
                                    } else {
                                        Log.e(TAG, "Missing CALL_PHONE permission for dial")
                                    }
                                } catch (e: SecurityException) {
                                    Log.e(TAG, "Permission denied for dial", e)
                                } catch (e: Exception) {
                                    Log.e(TAG, "Failed to dial", e)
                                }
                            }
                        }
                        else -> Log.w(TAG, "Unhandled message type: $msgType")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to parse/handle control message: ${e.message}")
                }
            }
        })
        }
    }

    private fun handleEndCall(ws: WebSocket?) {
        try {
            val tm = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val result = tm.endCall()
                Log.d(TAG, "Native endCall executed (result=$result)")
            } else {
                @Suppress("DEPRECATION")
                tm.silenceRinger()
                Log.d(TAG, "Native silenceRinger executed (legacy)")
            }
            Log.d(TAG, "SEND reject_call")
            sendAuthenticated("""{"type":"action_result","action":"end_call","success":true}""")
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission denied for end_call", e)
            sendAuthenticated("""{"type":"action_result","action":"end_call","success":false,"error":"Permission denied"}""")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to end call", e)
            sendAuthenticated("""{"type":"action_result","action":"end_call","success":false,"error":"${e.message}"}""")
        }
    }

    private fun syncContacts() {
        Log.d(TAG, "Syncing contacts...")
        try {
            val contactsArray = JSONArray()
            val uri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
            val projection = arrayOf(
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Phone.TYPE,
                ContactsContract.CommonDataKinds.Phone.LABEL
            )
            val cursor = contentResolver.query(uri, projection, null, null, null)

            val contactsMap = mutableMapOf<String, JSONObject>()

            cursor?.use {
                val idIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)
                val nameIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                val typeIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.TYPE)
                val labelIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.LABEL)

                while (it.moveToNext()) {
                    val id = it.getString(idIdx)
                    val name = it.getString(nameIdx) ?: ""
                    val num = it.getString(numIdx) ?: ""
                    val type = it.getInt(typeIdx)
                    var label = it.getString(labelIdx) ?: ""

                    if (label.isEmpty()) {
                        label = ContactsContract.CommonDataKinds.Phone.getTypeLabel(
                            resources, type, ""
                        ).toString()
                    }

                    val phoneObj = JSONObject().apply {
                        put("label", label)
                        put("number", num)
                    }

                    if (contactsMap.containsKey(id)) {
                        contactsMap[id]!!.getJSONArray("phones").put(phoneObj)
                    } else {
                        val cObj = JSONObject().apply {
                            put("id", id)
                            put("displayName", name)
                            val pArray = JSONArray().apply { put(phoneObj) }
                            put("phones", pArray)
                        }
                        contactsMap[id] = cObj
                    }
                }
            }

            for ((_, v) in contactsMap) {
                contactsArray.put(v)
            }

            val payload = JSONObject().apply {
                put("type", "contacts")
                put("contacts", contactsArray)
            }

            Log.d(TAG, "SEND contacts")
            sendAuthenticated(payload.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to sync contacts: ${e.message}")
        }
    }

    // ---------------------------------------------------------------
    // Telephony state — API-level branching. See docs/02_TDD.md §5.
    // ---------------------------------------------------------------

    private fun startPhoneListener() {
        if (isListenersStarted) return
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

        if (ContextCompat.checkSelfPermission(
                this,
                android.Manifest.permission.READ_PHONE_STATE
            ) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "READ_PHONE_STATE not granted — telephony listener not started")
            return
        }

        try {
            val receiver = object : android.content.BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
                        val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
                        var number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

                        if (number == null && latestScreenedNumber != null) {
                            number = latestScreenedNumber
                            latestScreenedNumber = null
                        }

                        val state = when (stateStr) {
                            TelephonyManager.EXTRA_STATE_RINGING -> TelephonyManager.CALL_STATE_RINGING
                            TelephonyManager.EXTRA_STATE_OFFHOOK -> TelephonyManager.CALL_STATE_OFFHOOK
                            else -> TelephonyManager.CALL_STATE_IDLE
                        }
                        handleStateChange(state, number)
                    }
                }
            }
            callStateReceiver = receiver
            val filter = android.content.IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
            registerReceiver(receiver, filter)

            val notifReceiver = object : android.content.BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == CallNotificationListenerService.ACTION_CALL_ANSWERED) {
                        if (lastState == TelephonyManager.CALL_STATE_OFFHOOK) {
                            sendAuthenticated("""{"type":"call_state","state":"answered"}""")
                            Log.d(TAG, "Sent call_state=answered (outgoing via notification)")
                        }
                    }
                }
            }
            notificationReceiver = notifReceiver
            val notifFilter = android.content.IntentFilter(CallNotificationListenerService.ACTION_CALL_ANSWERED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(notifReceiver, notifFilter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(notifReceiver, notifFilter)
            }

            isListenersStarted = true
            Log.i(TAG, "Telephony listeners registered")
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException registering telephony listener", e)
            // Degrades gracefully; the service won't crash, but it won't emit telephony updates.
        }
    }

    /** Shared by both the legacy and modern telephony callback paths. */
    private fun handleStateChange(state: Int, phoneNumber: String?) {
        val stateStr = when(state) {
            TelephonyManager.CALL_STATE_IDLE -> "IDLE"
            TelephonyManager.CALL_STATE_RINGING -> "RINGING"
            TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
            else -> "UNKNOWN"
        }
        Log.d(TAG, "Telephony state: $stateStr")

        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                val number = phoneNumber ?: "Unknown"
                val msg = """{"type":"incoming_call","phoneNumber":"$number","contactName":""}"""
                Log.d(TAG, "SEND incoming_call")
                sendAuthenticated(msg)
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                val isIncomingAnswered = lastState == TelephonyManager.CALL_STATE_RINGING
                val isOutgoingConnected = lastState == TelephonyManager.CALL_STATE_IDLE

                if (isIncomingAnswered) {
                    Log.d(TAG, "SEND call_state")
                    sendAuthenticated("""{"type":"call_state","state":"answered"}""")
                } else if (isOutgoingConnected) {
                    Log.d(TAG, "SEND call_state")
                    sendAuthenticated("""{"type":"call_state","state":"dialing"}""")
                }
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                if (lastState == TelephonyManager.CALL_STATE_RINGING ||
                    lastState == TelephonyManager.CALL_STATE_OFFHOOK
                ) {
                    Log.d(TAG, "SEND call_state")
                    sendAuthenticated("""{"type":"call_state","state":"ended"}""")
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

        networkCallback?.let {
            val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            connectivityManager.unregisterNetworkCallback(it)
        }
        networkCallback = null

        callStateReceiver?.let { unregisterReceiver(it) }
        callStateReceiver = null
        notificationReceiver?.let { unregisterReceiver(it) }
        notificationReceiver = null
        isListenersStarted = false
        running.set(false)

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
        @Volatile
        var latestScreenedNumber: String? = null
        val running = AtomicBoolean(false)
    }

    private fun sendAuthenticated(msg: String) {
        synchronized(socketLock) {
            if (!authenticated || webSocket == null) {
                Log.w(TAG, "Dropped message because connection is not authenticated: $msg")
                return
            }
            webSocket?.send(msg)
        }
    }
}
