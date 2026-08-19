package com.connecto.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkRequest
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.telecom.TelecomManager
import android.provider.CallLog
import android.database.ContentObserver
import android.provider.ContactsContract
import android.telephony.TelephonyManager
import android.widget.RemoteViews
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.util.Log
import android.hardware.camera2.CameraManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
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
    private var clipboardReceiver: android.content.BroadcastReceiver? = null
    private var batteryReceiver: android.content.BroadcastReceiver? = null

    private var previousCallState = TelephonyManager.CALL_STATE_IDLE
    private var lastState = TelephonyManager.CALL_STATE_IDLE
    private var missedCallNotificationId = 100
    private var lastEndedCallId: String? = null
    private var lastEndedTimestamp: Long = 0

    private var isRinging = false
    private var activeRingtone: android.media.Ringtone? = null
    private var ringTimeoutRunnable: Runnable? = null
    private var isFlashlightOn = false
    private var torchCallback: CameraManager.TorchCallback? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var isListenersStarted = false

    private var reconnectAttempt = 0
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onCreate() {
        super.onCreate()
        running.set(true)
        createNotificationChannel()
        startNetworkMonitoring()
        cleanupStaleShareCache()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            torchCallback = object : CameraManager.TorchCallback() {
                override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
                    isFlashlightOn = enabled
                    sendDeviceState()
                }
            }
            cameraManager.registerTorchCallback(torchCallback!!, mainHandler)
        }
    }

    /**
     * Deletes stale files in the dedicated Pakku share cache directory
     * (cacheDir/pakku_share/) that are older than 24 hours.
     *
     * This is a safety-net only. Files should be deleted immediately after
     * a successful send. Only files Pakku created (in pakku_share/) are touched.
     */
    private fun cleanupStaleShareCache() {
        try {
            val shareDir = java.io.File(cacheDir, "pakku_share")
            if (!shareDir.exists()) return
            val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
            shareDir.listFiles()?.forEach { file ->
                if (file.lastModified() < cutoff) {
                    file.delete()
                    Log.d(TAG, "Deleted stale share cache file: ${file.name}")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to clean share cache", e)
        }
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
        if (intent?.action == "com.connecto.app.ACTION_STOP_RINGING") {
            stopRinging()
            return START_STICKY
        } else if (intent?.action == "com.connecto.app.UNPAIR") {
            try {
                val json = JSONObject().apply { put("type", "unpair") }
                sendAuthenticated(json.toString())
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send unpair message", e)
            }
            val prefs = getSharedPreferences("pakku_prefs", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("paired", false).apply()
            
            val broadcastIntent = Intent("com.connecto.app.UNPAIRED")
            broadcastIntent.setPackage(packageName)
            sendBroadcast(broadcastIntent)
            
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                stopSelf()
            }, 500)
            return START_NOT_STICKY
        } else if (intent?.action == "com.connecto.app.SEND_MESSAGE") {
            val payload = intent.getStringExtra("payload")
            if (payload != null) {
                try {
                    sendAuthenticated(payload)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to send platform message", e)
                }
            }
            return START_STICKY
        } else if (intent?.action == "com.connecto.app.SEND_FILE_CHUNK") {
            Log.d("FileTransfer", "[PHASE7] Intent SEND_FILE_CHUNK received")
            val chunkPath = intent.getStringExtra("chunkPath")
            val transferId = intent.getStringExtra("transferId")
            val chunkIndex = intent.getIntExtra("chunkIndex", -1)
            val totalChunks = intent.getIntExtra("totalChunks", -1)
            Log.d("FileTransfer", "[PHASE7] Parsed intent extras: chunkPath=$chunkPath, transferId=$transferId, chunkIndex=$chunkIndex, totalChunks=$totalChunks")
            
            if (chunkPath != null && transferId != null && chunkIndex >= 0 && totalChunks > 0) {
                try {
                    val file = java.io.File(chunkPath)
                    
                    // Security Validation
                    val cacheDirPath = java.io.File(cacheDir, "connecto_transfer").canonicalPath
                    val canonicalFilePath = file.canonicalPath
                    if (!canonicalFilePath.startsWith(cacheDirPath)) {
                        throw SecurityException("Invalid chunk path")
                    }
                    if (file.name != "$chunkIndex.chunk") {
                        throw SecurityException("Invalid chunk filename")
                    }
                    if (!file.exists()) {
                        Log.e("FileTransfer", "[PHASE7] Chunk cache missing: $chunkPath")
                        return START_STICKY
                    }
                    if (file.length() > 1024 * 1024) { // >1MB
                        throw SecurityException("Chunk file too large")
                    }
                    
                    Log.d("FileTransfer", "[PHASE7] Reading chunk from cache")
                    
                    // Buffered Read
                    val buffer = CharArray(8192)
                    val builder = StringBuilder(file.length().toInt())
                    java.io.InputStreamReader(java.io.FileInputStream(file), Charsets.UTF_8).use { reader ->
                        var charsRead = reader.read(buffer)
                        while (charsRead != -1) {
                            builder.append(buffer, 0, charsRead)
                            charsRead = reader.read(buffer)
                        }
                    }
                    val base64Payload = builder.toString()
                    
                    val jsonStr = try {
                        org.json.JSONObject().apply {
                            put("type", "file.transfer.chunk")
                            put("transferId", transferId)
                            put("chunkIndex", chunkIndex)
                            put("totalChunks", totalChunks)
                            put("payload", base64Payload)
                        }.toString()
                    } catch(e: Exception) {
                        Log.e("FileTransfer", "[PHASE7] Chunk forwarding failed")
                        throw e
                    }
                    
                    Log.d("FileTransfer", "[PHASE7] Sending chunk over WebSocket")
                    
                    try {
                        sendAuthenticated(jsonStr)
                        Log.d("FileTransfer", "[PHASE7] Chunk forwarded successfully")
                        Log.d("FileTransfer", "[PHASE7] PhoneStateService forwarding chunk")
                    } catch (e: Exception) {
                        Log.e("FileTransfer", "[PHASE7] WebSocket chunk send failed", e)
                        // Keep file on disk if send fails
                    }
                } catch (e: Exception) {
                    Log.e("FileTransfer", "Failed to forward chunk from disk", e)
                }
            }
            return START_STICKY
        }

        val sendIntent = Intent(this, ClipboardReaderActivity::class.java).apply {
            action = ClipboardReaderActivity.ACTION_READ_CLIPBOARD
        }
        val pendingSendIntent = android.app.PendingIntent.getActivity(
            this,
            0,
            sendIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val remoteViews = RemoteViews(packageName, R.layout.notification_persistent)
        remoteViews.setOnClickPendingIntent(R.id.btn_send, pendingSendIntent)

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("Connecto")
            .setContentText("Connected to Mac")
            .setCustomContentView(remoteViews)
            .setCustomBigContentView(remoteViews)
            .setPriority(NotificationCompat.PRIORITY_MAX)
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
            
            var hmacSecret = ""
            try {
                val masterKey = androidx.security.crypto.MasterKey.Builder(this@PhoneStateService)
                    .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
                    .build()

                val securePrefs = androidx.security.crypto.EncryptedSharedPreferences.create(
                    this@PhoneStateService,
                    "FlutterSecureKeyStorage",
                    masterKey,
                    androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
                )
                hmacSecret = securePrefs.getString("VGhpc0lzVGhlUHJlZml4hmacSecret", "")?.removeSurrounding("\"")?.trim() ?: ""
            } catch (e: Exception) {
                android.util.Log.e("PhoneStateService", "Failed to read EncryptedSharedPreferences for hmacSecret: ${e.message}")
            }

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
                        val jwt = if (hmacSecret.isNotEmpty()) {
                            generateJwt(hmacSecret, android.os.Build.MODEL, "android_service")
                        } else {
                            "unprovisioned"
                        }

                        val helloMsg = JSONObject().apply {
                            put("type", "hello")
                            put("deviceName", android.os.Build.MODEL)
                            put("platform", "android_service")
                            put("jwt", jwt)
                        }
                        Log.d(TAG, "SEND hello")
                        webSocket.send(helloMsg.toString())
                        Log.d(TAG, "Waiting for auth_ack...")
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
                    if (!authenticated && msgType != "auth_ack") {
                        Log.w(TAG, "Dropped inbound message (unauthenticated): $msgType")
                        return
                    }
                    when (msgType) {
                        "auth_ack" -> {
                            Log.d(TAG, "Authentication successful")
                            authenticated = true
                            sendDeviceState()
                            syncCallHistory()
                            sendBatteryStatus(registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED)))
                            
                            // Synchronize current call state if one is active
                            val cid = trackedCallId
                            if (cid != null && lastState != TelephonyManager.CALL_STATE_IDLE) {
                                val stateStr = when (lastState) {
                                    TelephonyManager.CALL_STATE_OFFHOOK -> "active"
                                    TelephonyManager.CALL_STATE_RINGING -> "incoming"
                                    else -> "ended"
                                }
                                Log.d(TAG, "CALL_EVENT_SENT: $stateStr callId=$cid socketConnected=${webSocket != null} authenticated=$authenticated")
                                sendAuthenticated("""{"type":"call_state","callId":"$cid","state":"$stateStr"}""")
                            } else if (lastEndedCallId != null && (System.currentTimeMillis() - lastEndedTimestamp) < 10000) {
                                Log.d(TAG, "CALL_EVENT_SENT: ended callId=$lastEndedCallId socketConnected=${webSocket != null} authenticated=$authenticated")
                                sendAuthenticated("""{"type":"call_state","callId":"$lastEndedCallId","state":"ended"}""")
                            }
                        }
                        "unpair" -> {
                            Log.i(TAG, "Received unpair command")
                            val prefs = getSharedPreferences("pakku_prefs", Context.MODE_PRIVATE)
                            prefs.edit().putBoolean("paired", false).apply()
                            val broadcastIntent = Intent("com.connecto.app.UNPAIRED")
                            broadcastIntent.setPackage(packageName)
                            sendBroadcast(broadcastIntent)
                            stopSelf()
                        }
                        "contacts_request" -> {
                            syncContacts()
                        }
                        "request.call_history" -> {
                            syncCallHistory()
                        }
                        "set_ringer_mode" -> {
                            val mode = json.optString("mode")
                            handleSetRingerMode(mode)
                        }
                        "device_action" -> {
                            val action = json.optString("action")
                            val enabled = json.optBoolean("enabled", false)
                            handleDeviceAction(action, enabled)
                        }
                        "answer_call" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                try {
                                    val tm = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                                    tm.acceptRingingCall()
                                    Log.d(TAG, "Native answer executed")
                                    sendAuthenticated("""{"type":"action_result","action":"answer_call","success":true}""")
                                } catch (e: SecurityException) {
                                    Log.e(TAG, "Permission denied for acceptRingingCall", e)
                                    sendAuthenticated("""{"type":"action_result","action":"answer_call","success":false,"error":"Permission denied"}""")
                                } catch (e: Exception) {
                                    Log.e(TAG, "Failed to accept call", e)
                                    sendAuthenticated("""{"type":"action_result","action":"answer_call","success":false,"error":"${e.message}"}""")
                                }
                            } else {
                                Log.w(TAG, "acceptRingingCall requires API 28+")
                                sendAuthenticated("""{"type":"action_result","action":"answer_call","success":false,"error":"Requires API 28+"}""")
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
                                sendAuthenticated("""{"type":"action_result","action":"reject_call","success":true}""")
                            } catch (e: SecurityException) {
                                Log.e(TAG, "Permission denied for reject_call", e)
                                sendAuthenticated("""{"type":"action_result","action":"reject_call","success":false,"error":"Permission denied"}""")
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed to reject call", e)
                                sendAuthenticated("""{"type":"action_result","action":"reject_call","success":false,"error":"${e.message}"}""")
                            }
                        }
                        "end_call" -> {
                            handleEndCall(webSocket)
                        }
                        "dial" -> {
                            val number = json.optString("number")
                            val callId = json.optString("callId")
                            if (callId.isNotEmpty()) {
                                trackedCallId = callId
                            }
                            if (number.isNotEmpty()) {
                                try {
                                    val tm = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                                    if (ContextCompat.checkSelfPermission(this@PhoneStateService, android.Manifest.permission.CALL_PHONE) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                        tm.placeCall(Uri.parse("tel:$number"), android.os.Bundle())
                                        Log.d(TAG, "Native dial executed")
                                    } else {
                                        Log.e(TAG, "Missing CALL_PHONE permission for dial")
                                        throw SecurityException("Missing CALL_PHONE permission")
                                    }
                                } catch (e: SecurityException) {
                                    Log.e(TAG, "Permission denied for dial", e)
                                    sendAuthenticated("""{"type":"action_result","action":"dial","success":false,"error":"Permission denied"}""")
                                    if (callId.isNotEmpty()) {
                                        sendAuthenticated("""{"type":"call_state","callId":"$callId","state":"ended"}""")
                                    }
                                    trackedCallId = null
                                } catch (e: Exception) {
                                    Log.e(TAG, "Failed to dial", e)
                                    sendAuthenticated("""{"type":"action_result","action":"dial","success":false,"error":"${e.message}"}""")
                                    if (callId.isNotEmpty()) {
                                        sendAuthenticated("""{"type":"call_state","callId":"$callId","state":"ended"}""")
                                    }
                                    trackedCallId = null
                                }
                            }
                        }
                        "share.clipboard" -> {
                            // Failure contract: drop silently on any parsing error.
                            val schemaVersion = json.optInt("schemaVersion", -1)
                            if (schemaVersion != 1) return

                            val payloadObj  = json.optJSONObject("payload") ?: return
                            val contentObj  = payloadObj.optJSONObject("content") ?: return
                            val mime        = payloadObj.optString("mime").takeIf { it.isNotEmpty() } ?: return
                            val encoding    = contentObj.optString("encoding").takeIf { it.isNotEmpty() } ?: return
                            val body        = contentObj.optString("body").takeIf { it.isNotEmpty() } ?: return
                            val deviceName  = payloadObj.optString("deviceName").takeIf { it.isNotEmpty() } ?: "Mac"

                            val clipboardText: String? = if (encoding == "utf-8") body else null

                            var savedImagePath: String? = null
                            if (encoding == "base64" && mime.startsWith("image/")) {
                                // Payload size guard (5 MB on encoded payload).
                                if (body.length > 5 * 1024 * 1024) {
                                    Log.w(TAG, "Inbound image payload exceeds 5 MB limit — dropped.")
                                    return
                                }
                                try {
                                    val imageBytes = android.util.Base64.decode(body, android.util.Base64.DEFAULT)
                                    val shareDir   = java.io.File(cacheDir, "pakku_share").also { it.mkdirs() }
                                    shareDir.listFiles()?.forEach { file ->
                                        if (System.currentTimeMillis() - file.lastModified() > 3600000) {
                                            file.delete()
                                        }
                                    }
                                    val cacheFile  = java.io.File(shareDir, "recv_${System.currentTimeMillis()}.png")
                                    java.io.FileOutputStream(cacheFile).use { it.write(imageBytes) }
                                    savedImagePath = cacheFile.absolutePath
                                } catch (e: Exception) {
                                    Log.e(TAG, "Failed to decode/save received image — dropped", e)
                                    return
                                }
                            }

                            if (!clipboardText.isNullOrEmpty() || savedImagePath != null) {
                                if (MainActivity.isAppInForeground) {
                                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                                        try {
                                            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                                            val clip: android.content.ClipData
                                            var snippet = ""
                                            if (savedImagePath != null) {
                                                val file = java.io.File(savedImagePath)
                                                val uri = androidx.core.content.FileProvider.getUriForFile(this@PhoneStateService, "$packageName.fileprovider", file)
                                                clip = android.content.ClipData.newUri(contentResolver, "Copied from $deviceName", uri)
                                                snippet = "🖼️ Image"
                                            } else {
                                                clip = android.content.ClipData.newPlainText("Copied from $deviceName", clipboardText)
                                                snippet = if (clipboardText != null && clipboardText.length > 30) clipboardText.substring(0, 27) + "..." else (clipboardText ?: "")
                                            }
                                            clipboard.setPrimaryClip(clip)
                                            android.widget.Toast.makeText(this@PhoneStateService, "Copied from $deviceName\n$snippet", android.widget.Toast.LENGTH_SHORT).show()
                                        } catch (e: Exception) {
                                            Log.e(TAG, "Foreground copy failed", e)
                                        }
                                    }, 200)
                                } else {
                                    if (android.provider.Settings.canDrawOverlays(this@PhoneStateService)) {
                                        val intent = Intent(this@PhoneStateService, ClipboardWriterActivity::class.java).apply {
                                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
                                            putExtra("clipboard_text", clipboardText)
                                            if (savedImagePath != null) putExtra("image_path", savedImagePath)
                                            putExtra("device_name", deviceName)
                                        }
                                        startActivity(intent)
                                    } else {
                                        showClipboardNotification(clipboardText ?: "🖼️ Image", deviceName, savedImagePath)
                                    }
                                }
                            }

                            // Forward raw message to Flutter for deduplication tracking.
                            var payloadToBroadcast = text
                            if (encoding == "base64" && mime.startsWith("image/")) {
                                try {
                                    val newJson = org.json.JSONObject(text)
                                    val payload = newJson.optJSONObject("payload")
                                    val content = payload?.optJSONObject("content")
                                    if (content != null) {
                                        content.put("body", "") // Strip large body to avoid TransactionTooLargeException
                                        payloadToBroadcast = newJson.toString()
                                    }
                                } catch (e: Exception) {}
                            }

                            val broadcastIntent = Intent("com.connecto.app.WS_MESSAGE")
                            broadcastIntent.setPackage(packageName)
                            broadcastIntent.putExtra("payload", payloadToBroadcast)
                            sendBroadcast(broadcastIntent)

                            // Persist last received text natively as a fallback.
                            if (!clipboardText.isNullOrEmpty()) {
                                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                                prefs.edit().putString("flutter.lastReceivedClipboardText", clipboardText).apply()
                            }
                        }
                        else -> {
                            if (msgType.startsWith("file.transfer.")) {
                                Log.d(TAG, "[FT_BROADCAST_SENT] $text")
                                val broadcastIntent = Intent("com.connecto.app.FT_MESSAGE")
                                broadcastIntent.setPackage(packageName)
                                broadcastIntent.putExtra("secure_token", "INTERNAL_FT_SECURE_TOKEN")
                                broadcastIntent.putExtra("payload", text)
                                sendBroadcast(broadcastIntent)
                            }
                            // Only allowlist specific domain events for generic WS_MESSAGE broadcast.
                            else if (msgType.startsWith("call.") || 
                                msgType.startsWith("device.") || 
                                msgType.startsWith("battery.") || 
                                msgType.startsWith("status.") ||
                                msgType.startsWith("notification.")) {
                                
                                val broadcastIntent = Intent("com.connecto.app.WS_MESSAGE")
                                broadcastIntent.setPackage(packageName)
                                broadcastIntent.putExtra("payload", text)
                                sendBroadcast(broadcastIntent)
                            } else {
                                Log.d(TAG, "Silently dropping protocol/unrecognized message ($msgType) from WS_MESSAGE broadcast")
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to parse/handle control message: ${e.message}")
                }
            }
        })
        }
    }

    private fun generateJwt(secret: String, deviceName: String, platform: String): String {
        val header = JSONObject().apply {
            put("alg", "HS256")
            put("typ", "JWT")
        }
        val now = System.currentTimeMillis() / 1000
        val payload = JSONObject().apply {
            put("iss", "connecto")
            put("sub", "android_" + android.os.Build.MODEL)
            put("aud", "connecto_client")
            put("iat", now)
            put("nbf", now)
            put("exp", now + 300)
            put("device_id", "android_" + android.os.Build.MODEL)
            put("device_name", deviceName)
            put("platform", platform)
            put("jti", java.util.UUID.randomUUID().toString())
        }
        val h = android.util.Base64.encodeToString(header.toString().toByteArray(), android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP)
        val p = android.util.Base64.encodeToString(payload.toString().toByteArray(), android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP)
        
        val mac = javax.crypto.Mac.getInstance("HmacSHA256")
        mac.init(javax.crypto.spec.SecretKeySpec(secret.toByteArray(), "HmacSHA256"))
        val sigBytes = mac.doFinal("$h.$p".toByteArray())
        val sig = android.util.Base64.encodeToString(sigBytes, android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP)
        return "$h.$p.$sig"
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

    private fun syncCallHistory() {
        Log.d(TAG, "Syncing call history...")
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_CALL_LOG) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "READ_CALL_LOG permission not granted. Skipping call history sync.")
            return
        }
        try {
            val callsArray = JSONArray()
            val uri = CallLog.Calls.CONTENT_URI
            val projection = arrayOf(
                CallLog.Calls._ID,
                CallLog.Calls.NUMBER,
                CallLog.Calls.CACHED_NAME,
                CallLog.Calls.TYPE,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION
            )
            val sortOrder = "${CallLog.Calls.DATE} DESC"
            val cursor = contentResolver.query(uri, projection, null, null, sortOrder)

            cursor?.use {
                val idIdx = it.getColumnIndex(CallLog.Calls._ID)
                val numberIdx = it.getColumnIndex(CallLog.Calls.NUMBER)
                val nameIdx = it.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val typeIdx = it.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = it.getColumnIndex(CallLog.Calls.DATE)
                val durationIdx = it.getColumnIndex(CallLog.Calls.DURATION)

                var count = 0
                while (it.moveToNext() && count < 100) {
                    count++
                    val id = it.getString(idIdx)
                    val number = it.getString(numberIdx) ?: ""
                    val name = it.getString(nameIdx) ?: ""
                    val typeInt = it.getInt(typeIdx)
                    val date = it.getLong(dateIdx)
                    val duration = it.getLong(durationIdx)

                    val typeStr = when (typeInt) {
                        CallLog.Calls.INCOMING_TYPE -> "incoming"
                        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                        CallLog.Calls.MISSED_TYPE -> "missed"
                        CallLog.Calls.REJECTED_TYPE -> "rejected"
                        CallLog.Calls.VOICEMAIL_TYPE -> "voicemail"
                        CallLog.Calls.BLOCKED_TYPE -> "blocked"
                        else -> "unknown"
                    }

                    val callObj = JSONObject().apply {
                        put("id", id)
                        put("name", name)
                        put("number", number)
                        put("type", typeStr)
                        put("timestamp", date) // Using ms timestamp
                        put("duration", duration)
                    }
                    callsArray.put(callObj)
                }
            }

            val payloadObj = JSONObject().apply {
                put("calls", callsArray)
            }

            val envelope = JSONObject().apply {
                put("schemaVersion", 1)
                put("type", "sync.call_history")
                put("timestamp", System.currentTimeMillis() / 1000)
                put("payload", payloadObj)
            }

            Log.d(TAG, "SEND sync.call_history")
            sendAuthenticated(envelope.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to sync call history: ${e.message}")
        }
    }

    private fun showClipboardNotification(text: String, deviceName: String, imagePath: String?) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        val channelId = "pakku_clipboard_channel"
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                channelId,
                "Clipboard Sync",
                android.app.NotificationManager.IMPORTANCE_HIGH
            )
            manager.createNotificationChannel(channel)
        }

        val intent = Intent(this, ClipboardWriterActivity::class.java).apply {
            putExtra("clipboard_text", text)
            if (imagePath != null) {
                putExtra("image_path", imagePath)
            }
            putExtra("device_name", deviceName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        
        val pendingIntent = android.app.PendingIntent.getActivity(
            this,
            (text + (imagePath ?: "")).hashCode(),
            intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = androidx.core.app.NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setContentTitle("Clipboard from $deviceName")
            .setContentText(if (imagePath != null) "🖼️ Image - Tap to copy" else "Tap to copy to your phone")
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .addAction(android.R.drawable.ic_menu_save, "Copy", pendingIntent)
            .setContentIntent(pendingIntent)
            .build()
            
        manager.notify(80085, notification)
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

        batteryReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_BATTERY_CHANGED) {
                    sendBatteryStatus(intent)
                }
            }
        }
        registerReceiver(batteryReceiver, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))

        try {
            val callLogObserver = object : ContentObserver(mainHandler) {
                override fun onChange(selfChange: Boolean) {
                    super.onChange(selfChange)
                    syncCallHistory()
                }
            }
            contentResolver.registerContentObserver(CallLog.Calls.CONTENT_URI, true, callLogObserver)
            
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
                            val cid = trackedCallId ?: ""
                            sendAuthenticated("""{"type":"call_state","callId":"$cid","state":"active"}""")
                            Log.d(TAG, "Sent call_state=active (outgoing via notification)")
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

            val clipReceiver = object : android.content.BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action != "com.connecto.app.ACTION_SEND_TO_MAC") return
                    val text      = intent.getStringExtra("text")
                    val imagePath = intent.getStringExtra("imagePath")
                    if (text.isNullOrEmpty() && imagePath.isNullOrEmpty()) return

                    // Run image processing on a background thread so the
                    // broadcast receiver returns immediately.
                    Thread {
                        var encodedBody: String? = null
                        var mime = "text/plain"
                        var metadata: JSONObject? = null

                        if (!imagePath.isNullOrEmpty()) {
                            val cacheFile = java.io.File(imagePath)
                            try {
                                // Determine MIME type. ContentResolver not available from
                                // a broadcast receiver without a Uri, so resolve from path.
                                // Decoding to Bitmap strips all EXIF (GPS, camera, orientation,
                                // timestamps) from the resulting pixel buffer.
                                val bitmap = android.graphics.BitmapFactory.decodeFile(imagePath)
                                if (bitmap == null) {
                                    Log.w(TAG, "Failed to decode image bitmap — dropped.")
                                    cacheFile.delete()
                                    return@Thread
                                }

                                val maxEncoded = 5 * 1024 * 1024 // 5 MB (encoded payload limit)

                                // Try PNG first.
                                var outStream = java.io.ByteArrayOutputStream()
                                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, outStream)
                                var bytes = outStream.toByteArray()
                                var encodedSize = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP).length

                                if (encodedSize <= maxEncoded) {
                                    mime = "image/png"
                                } else {
                                    // Binary search JPEG quality: range 30–100, max 7 iterations.
                                    // Target: encoded payload (Base64) size <= 5 MB.
                                    var lo = 30; var hi = 100
                                    var bestBytes: ByteArray? = null
                                    var iterations = 0
                                    while (lo <= hi && iterations < 7) {
                                        val mid = (lo + hi) / 2
                                        outStream = java.io.ByteArrayOutputStream()
                                        bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, mid, outStream)
                                        val candidate = outStream.toByteArray()
                                        val candidateEncoded = android.util.Base64.encodeToString(candidate, android.util.Base64.NO_WRAP).length
                                        if (candidateEncoded <= maxEncoded) {
                                            bestBytes = candidate
                                            lo = mid + 1  // try higher quality
                                        } else {
                                            hi = mid - 1  // reduce quality
                                        }
                                        iterations++
                                    }
                                    if (bestBytes == null) {
                                        Log.w(TAG, "Image too large to fit in 5 MB even at min quality — dropped.")
                                        mainHandler.post {
                                            android.widget.Toast.makeText(this@PhoneStateService, "Image too large to send", android.widget.Toast.LENGTH_SHORT).show()
                                        }
                                        cacheFile.delete()
                                        return@Thread
                                    }
                                    bytes = bestBytes
                                    mime  = "image/jpeg"
                                }

                                encodedBody = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
                                metadata = JSONObject().apply {
                                    put("width",     bitmap.width)
                                    put("height",    bitmap.height)
                                    put("sizeBytes", bytes.size)
                                    // displayName is optional — omit if unknown.
                                }

                                // Immediate cache cleanup after successful encoding.
                                cacheFile.delete()
                                Log.d(TAG, "Deleted share cache file after encode: ${cacheFile.name}")

                            } catch (e: Exception) {
                                Log.e(TAG, "Failed to encode image — dropped", e)
                                cacheFile.delete()
                                return@Thread
                            }
                        } else if (!text.isNullOrEmpty()) {
                            encodedBody = text
                            mime = "text/plain"
                        }

                        if (encodedBody == null) return@Thread

                        val contentObj = JSONObject().apply {
                            put("encoding", if (mime == "text/plain") "utf-8" else "base64")
                            put("body", encodedBody)
                            if (metadata != null) put("metadata", metadata)
                        }

                        // Compute SHA-256 for image payloads only (required by macOS validation).
                        val sha256: String? = if (mime != "text/plain") {
                            try {
                                val digest = java.security.MessageDigest.getInstance("SHA-256")
                                val hashBytes = digest.digest(
                                    android.util.Base64.decode(encodedBody, android.util.Base64.NO_WRAP)
                                )
                                hashBytes.joinToString("") { "%02x".format(it) }
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed to compute sha256 — image dropped", e)
                                return@Thread
                            }
                        } else null

                        val innerPayload = JSONObject().apply {
                            put("id",         java.util.UUID.randomUUID().toString())
                            put("mime",       mime)
                            put("deviceName", android.os.Build.MODEL)
                            put("content",    contentObj)
                            if (sha256 != null) put("sha256", sha256)
                        }

                        val payload = JSONObject().apply {
                            put("schemaVersion", 1)
                            put("type", "share.clipboard")
                            put("timestamp", System.currentTimeMillis())
                            put("payload", innerPayload)
                        }
                        Log.d(TAG, "SEND outbound share (mime=$mime)")
                        sendAuthenticated(payload.toString())
                    }.start()
                }
            }
            clipboardReceiver = clipReceiver
            val clipFilter = android.content.IntentFilter("com.connecto.app.ACTION_SEND_TO_MAC")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(clipReceiver, clipFilter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(clipReceiver, clipFilter)
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
        Log.d(TAG, "PhoneStateReceiver triggered")
        val stateStr = when(state) {
            TelephonyManager.CALL_STATE_IDLE -> "IDLE"
            TelephonyManager.CALL_STATE_RINGING -> "RINGING"
            TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
            else -> "UNKNOWN"
        }
        val prevStr = when(previousCallState) {
            TelephonyManager.CALL_STATE_IDLE -> "IDLE"
            TelephonyManager.CALL_STATE_RINGING -> "RINGING"
            TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
            else -> "UNKNOWN"
        }
        Log.d(TAG, "PHONE_STATE_CHANGE\nprevious=$prevStr\ncurrent=$stateStr\ntrackedCallId=$trackedCallId\nwebsocketConnected=${webSocket != null}\nauthenticated=$authenticated")

        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                val number = phoneNumber ?: "Unknown"
                if (trackedCallId == null) {
                    trackedCallId = java.util.UUID.randomUUID().toString()
                    trackedPhoneNumber = number
                    trackedContactName = getContactName(number)
                }
                val callId = trackedCallId ?: ""
                Log.d(TAG, "CALL_LIFECYCLE\nstate=RINGING\ncallId=$callId")
                
                // Use resolved contact name in the websocket message if available, else empty string
                val cName = trackedContactName ?: ""
                val msg = """{"type":"incoming_call","callId":"$callId","phoneNumber":"$number","contactName":"$cName"}"""
                Log.d(TAG, "CALL_EVENT_SENT: incoming callId=$callId socketConnected=${webSocket != null} authenticated=$authenticated")
                sendAuthenticated(msg)
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                lastEndedCallId = trackedCallId
                val isIncomingAnswered = lastState == TelephonyManager.CALL_STATE_RINGING
                val isOutgoingConnected = lastState == TelephonyManager.CALL_STATE_IDLE
                val cid = trackedCallId ?: ""
                Log.d(TAG, "CALL_LIFECYCLE\nstate=OFFHOOK\ncallId=$cid")

                if (isIncomingAnswered) {
                    Log.d(TAG, "CALL_EVENT_SENT: active callId=$cid socketConnected=${webSocket != null} authenticated=$authenticated")
                    sendAuthenticated("""{"type":"call_state","callId":"$cid","state":"active"}""")
                } else if (isOutgoingConnected) {
                    Log.d(TAG, "CALL_EVENT_SENT: dialing callId=$cid socketConnected=${webSocket != null} authenticated=$authenticated")
                    sendAuthenticated("""{"type":"call_state","callId":"$cid","state":"dialing"}""")
                }
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                lastEndedTimestamp = System.currentTimeMillis()
                lastEndedCallId = trackedCallId
                val cid = trackedCallId ?: ""
                Log.d(TAG, "CALL_LIFECYCLE\nstate=IDLE\ncallId=$cid")
                Log.d(TAG, "CALL_EVENT_SENT: ended callId=$cid socketConnected=${webSocket != null} authenticated=$authenticated")
                sendAuthenticated("""{"type":"call_state","callId":"$cid","state":"ended"}""")
                Log.d(TAG, "ENDED_EVENT_DISPATCHED callId=$cid")
                
                // Missed call: went straight from RINGING to IDLE, never OFFHOOK.
                if (lastState == TelephonyManager.CALL_STATE_RINGING) {
                    showMissedCallNotification()
                }
                
                trackedCallId = null
                trackedPhoneNumber = null
                trackedContactName = null
            }
        }
        previousCallState = lastState
        lastState = state
    }


    private fun sendDeviceState() {
        if (!authenticated) return
        try {
            val json = JSONObject().apply {
                put("type", "device_state")
                put("state", "connected")
                put("ringing", isRinging)
                put("flashlight", isFlashlightOn)
                
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val ringerMode = when (audioManager.ringerMode) {
                    AudioManager.RINGER_MODE_SILENT -> "silent"
                    AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                    else -> "normal"
                }
                put("mode", ringerMode)
            }
            sendAuthenticated(json.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send device state", e)
        }
    }

    private fun stopRinging() {
        if (!isRinging) return
        
        activeRingtone?.stop()
        activeRingtone = null
        
        ringTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        ringTimeoutRunnable = null
        
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(101)
        
        isRinging = false
        sendDeviceState()
    }

    private fun showRingingNotification() {
        val stopIntent = Intent(this, PhoneStateService::class.java).apply {
            action = "com.connecto.app.ACTION_STOP_RINGING"
        }
        val pendingIntent = PendingIntent.getService(this, 0, stopIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        
        val channelId = "ring_channel"
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Find My Phone", NotificationManager.IMPORTANCE_HIGH)
            manager.createNotificationChannel(channel)
        }
        
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("Connecto")
            .setContentText("Phone is ringing")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_media_pause, "STOP RINGING", pendingIntent)
            .build()
            
        manager.notify(101, notification)
    }

    private fun getContactName(phoneNumber: String): String? {
        if (phoneNumber == "Unknown") return null
        val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(phoneNumber))
        val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)
        var contactName: String? = null
        try {
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    contactName = cursor.getString(0)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error looking up contact name: ${e.message}")
        }
        return contactName
    }

    private fun showMissedCallNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        
        val displayNumber = trackedPhoneNumber ?: "Unknown"
        val displayName = trackedContactName
        
        // Use BigTextStyle to format Name and Number clearly
        val style = NotificationCompat.BigTextStyle()
            .bigText(if (displayName != null) "$displayName\n$displayNumber" else displayNumber)
            
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Missed Call")
            .setContentText(displayName ?: displayNumber) // fallback for collapsed view
            .setStyle(style)
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
        httpClient?.let { client ->
            Thread {
                client.dispatcher.cancelAll()
                client.dispatcher.executorService.shutdown()
                client.connectionPool.evictAll()
            }.start()
        }
        httpClient = null

        networkCallback?.let {
            val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            connectivityManager.unregisterNetworkCallback(it)
        }
        networkCallback = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            torchCallback?.let {
                val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                cameraManager.unregisterTorchCallback(it)
            }
        }
        torchCallback = null

        callStateReceiver?.let { unregisterReceiver(it) }
        callStateReceiver = null
        notificationReceiver?.let { unregisterReceiver(it) }
        notificationReceiver = null
        clipboardReceiver?.let { unregisterReceiver(it) }
        clipboardReceiver = null
        batteryReceiver?.let { unregisterReceiver(it) }
        batteryReceiver = null
        isListenersStarted = false
        running.set(false)

        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private var mediaPlayer: MediaPlayer? = null

    private fun sendBatteryStatus(intent: Intent?) {
        if (intent == null) return
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)
        val health = intent.getIntExtra(BatteryManager.EXTRA_HEALTH, -1)
        val temperature = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)

        val percentage = if (level >= 0 && scale > 0) (level * 100f / scale).toInt() else -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || plugged > 0
        
        var chargeTimeRemaining = -1L
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            chargeTimeRemaining = batteryManager.computeChargeTimeRemaining()
            if (chargeTimeRemaining > 0) {
                chargeTimeRemaining /= (1000 * 60) // convert ms to minutes
            }
        }

        val healthStr = when (health) {
            BatteryManager.BATTERY_HEALTH_GOOD -> "excellent"
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheating"
            BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "over_voltage"
            BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "failure"
            BatteryManager.BATTERY_HEALTH_COLD -> "cold"
            else -> "unknown"
        }

        val json = JSONObject().apply {
            put("type", "battery_status")
            put("level", percentage)
            put("charging", isCharging)
            put("temperature", temperature / 10.0)
            put("health", healthStr)
            put("chargeTimeRemaining", chargeTimeRemaining)
            put("timestamp", System.currentTimeMillis() / 1000)
        }
        sendAuthenticated(json.toString())
    }

    private fun handleSetRingerMode(mode: String) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        val modeInt = when (mode) {
            "silent" -> AudioManager.RINGER_MODE_SILENT
            "vibrate" -> AudioManager.RINGER_MODE_VIBRATE
            else -> AudioManager.RINGER_MODE_NORMAL
        }

        if (modeInt == AudioManager.RINGER_MODE_SILENT && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!notificationManager.isNotificationPolicyAccessGranted) {
                sendAuthenticated("""{"type":"action_result","action":"set_ringer_mode","status":"permission_required"}""")
                val intent = Intent(android.provider.Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return
            }
        }

        try {
            audioManager.ringerMode = modeInt
            sendAuthenticated("""{"type":"action_result","action":"set_ringer_mode","status":"success"}""")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set ringer mode", e)
            sendAuthenticated("""{"type":"action_result","action":"set_ringer_mode","status":"error","error":"${e.message}"}""")
        }
    }

    private fun handleDeviceAction(action: String, enabled: Boolean) {
        when (action) {
            "flashlight" -> {
                try {
                    val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                    val cameraId = cameraManager.cameraIdList.firstOrNull { 
                        cameraManager.getCameraCharacteristics(it).get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE) == true 
                    }
                    if (cameraId != null) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            cameraManager.setTorchMode(cameraId, enabled)
                            sendAuthenticated("""{"type":"action_result","action":"flashlight","status":"success","enabled":$enabled}""")
                        } else {
                            sendAuthenticated("""{"type":"action_result","action":"flashlight","status":"error","error":"Requires Android M+"}""")
                        }
                    } else {
                        sendAuthenticated("""{"type":"action_result","action":"flashlight","status":"error","error":"No flash available"}""")
                    }
                } catch (e: Exception) {
                    sendAuthenticated("""{"type":"action_result","action":"flashlight","status":"error","error":"${e.message}"}""")
                }
            }
            "ring" -> {
                try {
                    if (enabled) {
                        if (isRinging) stopRinging()
                        
                        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                        activeRingtone = RingtoneManager.getRingtone(this, uri)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            activeRingtone?.isLooping = true
                        }
                        
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            val audioAttributes = android.media.AudioAttributes.Builder()
                                .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                            activeRingtone?.audioAttributes = audioAttributes
                        } else {
                            @Suppress("DEPRECATION")
                            activeRingtone?.streamType = AudioManager.STREAM_ALARM
                        }
                        
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxVol, 0)
                        
                        activeRingtone?.play()
                        isRinging = true
                        
                        showRingingNotification()
                        
                        ringTimeoutRunnable = Runnable { stopRinging() }
                        mainHandler.postDelayed(ringTimeoutRunnable!!, 30000)
                        
                        sendAuthenticated("""{"type":"action_result","action":"ring","status":"success","enabled":true}""")
                    } else {
                        stopRinging()
                        sendAuthenticated("""{"type":"action_result","action":"ring","status":"success","enabled":false}""")
                    }
                } catch (e: Exception) {
                    sendAuthenticated("""{"type":"action_result","action":"ring","status":"error","error":"${e.message}"}""")
                }
            }
            "lock" -> {
                val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                val adminComponent = ComponentName(this, PakkuDeviceAdminReceiver::class.java)
                
                if (dpm.isAdminActive(adminComponent)) {
                    dpm.lockNow()
                    sendAuthenticated("""{"type":"action_result","action":"lock","status":"success"}""")
                } else {
                    sendAuthenticated("""{"type":"action_result","action":"lock","status":"permission_required"}""")
                    val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                        putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                        putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Required to remotely lock the phone from your Mac.")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                }
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Call Service", NotificationManager.IMPORTANCE_HIGH)
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    companion object {
        private const val TAG = "PhoneStateService"
        private const val CHANNEL_ID = "PhoneStateServiceChannel_v3"
        @Volatile
        var latestScreenedNumber: String? = null
        val running = AtomicBoolean(false)
        @Volatile
        var trackedCallId: String? = null
        @Volatile
        var trackedPhoneNumber: String? = null
        @Volatile
        var trackedContactName: String? = null
    }

    private fun sendAuthenticated(msg: String) {
        synchronized(socketLock) {
            if (!authenticated || webSocket == null) {
                Log.w(TAG, "Dropped outbound message (unauthenticated).")
                return
            }
            try {
                val json = JSONObject(msg)
                val type = json.optString("type", "unknown")
                Log.d(TAG, "WS_SEND type=\$type")
            } catch (e: Exception) {
                Log.d(TAG, "WS_SEND type=unknown")
            }
            webSocket?.send(msg)
        }
    }
}
