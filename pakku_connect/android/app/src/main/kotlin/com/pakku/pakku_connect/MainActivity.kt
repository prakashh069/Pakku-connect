package com.pakku.pakku_connect

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
    private val CHANNEL = "com.pakku.connect/platform"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
                        getSharedPreferences("pakku_prefs", Context.MODE_PRIVATE)
                            .edit()
                            .putString("ws_ip", ip)
                            .putInt("ws_port", port)
                            .putString("cert_fp", certFp)
                            .apply()
                        result.success(true)
                    }
                    "requestCallLogPermission" -> {
                        // Fire-and-forget by design — see docs/04_IMPLEMENTATION_GUIDE.md
                        // §8.2 and docs/02_TDD.md §5.1. Denial degrades caller-ID display
                        // to "Unknown"; it never blocks pairing or crashes the service.
                        if (ContextCompat.checkSelfPermission(
                                this, Manifest.permission.READ_CALL_LOG
                            ) != PackageManager.PERMISSION_GRANTED
                        ) {
                            ActivityCompat.requestPermissions(
                                this, arrayOf(Manifest.permission.READ_CALL_LOG), REQ_CALL_LOG)
                        }
                        result.success(true)
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
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val REQ_CALL_PHONE = 101
        private const val REQ_CALL_LOG = 102
    }
}
