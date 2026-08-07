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
import android.widget.RemoteViews
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
    private var clipboardReceiver: android.content.BroadcastReceiver? = null

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
        cleanupStaleShareCache()
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
        } else if (intent?.action == "com.pakku.pakku_connect.SEND_MESSAGE") {
            val payload = intent.getStringExtra("payload")
            if (payload != null) {
                try {
                    sendAuthenticated(payload)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to send platform message", e)
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
            .setContentTitle("Pakku Connect")
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

                            val broadcastIntent = Intent("com.pakku.pakku_connect.WS_MESSAGE")
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
                            val broadcastIntent = Intent("com.pakku.pakku_connect.WS_MESSAGE")
                            broadcastIntent.setPackage(packageName)
                            broadcastIntent.putExtra("payload", text)
                            sendBroadcast(broadcastIntent)
                        }
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

            val clipReceiver = object : android.content.BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action != "com.pakku.pakku_connect.ACTION_SEND_TO_MAC") return
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

                        val payload = JSONObject().apply {
                            put("schemaVersion", 1)
                            put("type", "share.clipboard")
                            put("timestamp", System.currentTimeMillis())
                            put("payload", JSONObject().apply {
                                put("id",         java.util.UUID.randomUUID().toString())
                                put("mime",       mime)
                                put("deviceName", android.os.Build.MODEL)
                                put("content",    contentObj)
                            })
                        }
                        Log.d(TAG, "SEND outbound share (mime=$mime)")
                        sendAuthenticated(payload.toString())
                    }.start()
                }
            }
            clipboardReceiver = clipReceiver
            val clipFilter = android.content.IntentFilter("com.pakku.pakku_connect.ACTION_SEND_TO_MAC")
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
        clipboardReceiver?.let { unregisterReceiver(it) }
        clipboardReceiver = null
        isListenersStarted = false
        running.set(false)

        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

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
    }

    private fun sendAuthenticated(msg: String) {
        synchronized(socketLock) {
            if (!authenticated || webSocket == null) {
                Log.w(TAG, "Dropped outbound message (unauthenticated).")
                return
            }
            webSocket?.send(msg)
        }
    }
}
