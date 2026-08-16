package com.connecto.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.connecto.app/platform"
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val unpairedReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            flutterEngine?.let { engine ->
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).invokeMethod("onUnpaired", null)
            }
        }
    }

    private val wsMessageReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val payload = intent?.getStringExtra("payload") ?: return
            flutterEngine?.let { engine ->
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).invokeMethod("onMessage", payload)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(unpairedReceiver, android.content.IntentFilter("com.connecto.app.UNPAIRED"), Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(wsMessageReceiver, android.content.IntentFilter("com.connecto.app.WS_MESSAGE"), Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(unpairedReceiver, android.content.IntentFilter("com.connecto.app.UNPAIRED"))
            registerReceiver(wsMessageReceiver, android.content.IntentFilter("com.connecto.app.WS_MESSAGE"))
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestCallScreeningRole" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val roleManager = getSystemService(Context.ROLE_SERVICE) as android.app.role.RoleManager
                            if (roleManager.isRoleHeld(android.app.role.RoleManager.ROLE_CALL_SCREENING)) {
                                result.success(true)
                            } else {
                                val intent = roleManager.createRequestRoleIntent(android.app.role.RoleManager.ROLE_CALL_SCREENING)
                                startActivityForResult(intent, 1)
                                result.success(true)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "makeCall" -> {
                        val number = call.argument<String>("phoneNumber")
                        if (number == null) {
                            result.error("INVALID", "phoneNumber required", null)
                            return@setMethodCallHandler
                        }
                        if (ContextCompat.checkSelfPermission(
                                this, Manifest.permission.CALL_PHONE
                            ) == PackageManager.PERMISSION_GRANTED
                        ) {
                            startActivity(Intent(Intent.ACTION_CALL, Uri.parse("tel:$number")))
                            result.success(true)
                        } else {
                            ActivityCompat.requestPermissions(
                                this, arrayOf(Manifest.permission.CALL_PHONE), REQ_CALL_PHONE)
                            result.error("PERMISSION", "CALL_PHONE not granted", null)
                        }
                    }
                    "saveWsEndpoint" -> {
                        val ip = call.argument<String>("ip")
                        val port = call.argument<Int>("port") ?: 8080
                        val certFp = call.argument<String>("certFp")
                        val hmacSecret = call.argument<String>("hmacSecret")
                        
                        try {
                            val masterKey = androidx.security.crypto.MasterKey.Builder(this)
                                .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
                                .build()

                            val securePrefs = androidx.security.crypto.EncryptedSharedPreferences.create(
                                this,
                                "FlutterSecureKeyStorage",
                                masterKey,
                                androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                                androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
                            )
                            securePrefs.edit().putString("VGhpc0lzVGhlUHJlZml4hmacSecret", hmacSecret).apply()
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Failed to save hmacSecret to EncryptedSharedPreferences: ${e.message}")
                        }

                        getSharedPreferences("pakku_prefs", Context.MODE_PRIVATE)
                            .edit()
                            .putString("ws_ip", ip)
                            .putInt("ws_port", port)
                            .putString("cert_fp", certFp)
                            .apply()
                        result.success(true)
                    }
                    "hasNotificationAccess" -> {
                        val listeners = android.provider.Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                        val isGranted = listeners != null && listeners.contains(packageName)
                        result.success(isGranted)
                    }
                    "requestNotificationAccess" -> {
                        val listeners = android.provider.Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                        val isGranted = listeners != null && listeners.contains(packageName)
                        if (!isGranted) {
                            val intent = Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    "hasOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            result.success(android.provider.Settings.canDrawOverlays(this@MainActivity))
                        } else {
                            result.success(true)
                        }
                    }
                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            if (!android.provider.Settings.canDrawOverlays(this@MainActivity)) {
                                val intent = Intent(
                                    android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(intent)
                            }
                        }
                        result.success(true)
                    }
                    "requestAllPermissions" -> {
                        val permissionsToRequest = mutableListOf(
                            Manifest.permission.CALL_PHONE,
                            Manifest.permission.READ_PHONE_STATE,
                            Manifest.permission.READ_CONTACTS,
                            Manifest.permission.READ_CALL_LOG
                        )
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            permissionsToRequest.add(Manifest.permission.ANSWER_PHONE_CALLS)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            permissionsToRequest.add(Manifest.permission.POST_NOTIFICATIONS)
                            permissionsToRequest.add(Manifest.permission.READ_MEDIA_IMAGES)
                        } else {
                            permissionsToRequest.add(Manifest.permission.READ_EXTERNAL_STORAGE)
                        }

                        val ungranted = permissionsToRequest.filter {
                            ContextCompat.checkSelfPermission(this@MainActivity, it) != PackageManager.PERMISSION_GRANTED
                        }

                        if (ungranted.isEmpty()) {
                            result.success(true)
                        } else {
                            pendingPermissionResult = result
                            ActivityCompat.requestPermissions(
                                this@MainActivity,
                                ungranted.toTypedArray(),
                                REQ_ALL_PERMISSIONS
                            )
                        }
                    }
                    "startPhoneStateService" -> {
                        val intent = Intent(this, PhoneStateService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "unpair" -> {
                        val intent = Intent(this, PhoneStateService::class.java).apply {
                            action = "com.connecto.app.UNPAIR"
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "sendPlatformMessage" -> {
                        val payload = call.arguments<String>()
                        if (payload != null) {
                            val intent = Intent(this, PhoneStateService::class.java).apply {
                                action = "com.connecto.app.SEND_MESSAGE"
                                putExtra("payload", payload)
                            }
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "getDeviceName" -> {
                        result.success(android.os.Build.MODEL)
                    }
                    "getClipboardData" -> {
                        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                        if (!clipboard.hasPrimaryClip()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val clip = clipboard.primaryClip
                        val text = clip?.getItemAt(0)?.text?.toString()
                        val label = clipboard.primaryClipDescription?.label?.toString()
                        
                        val isRemote = label?.startsWith("Copied from") == true
                        
                        val data = mapOf(
                            "text" to text,
                            "isRemote" to isRemote
                        )
                        result.success(data)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(unpairedReceiver)
        unregisterReceiver(wsMessageReceiver)
    }

    override fun onResume() {
        super.onResume()
        isAppInForeground = true
    }

    override fun onPause() {
        super.onPause()
        isAppInForeground = false
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == REQ_ALL_PERMISSIONS) {
            val granted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    companion object {
        var isAppInForeground = false
        private const val REQ_CALL_PHONE = 101
        private const val REQ_ALL_PERMISSIONS = 102
    }
}
