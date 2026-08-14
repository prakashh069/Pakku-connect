package com.pakku.pakku_connect

import android.content.Context
import android.provider.CallLog
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

class CallHistoryRepository(private val context: Context) {

    companion object {
        private const val TAG = "CallHistoryRepository"
    }

    /**
     * Queries the CallLog, enforcing privacy constraints and returning a JSON payload
     * formatted as a `sync.call_history` message.
     */
    fun getRecentCallsPayload(): JSONObject {
        val callsArray = JSONArray()
        
        try {
            val uri = CallLog.Calls.CONTENT_URI
            val projection = arrayOf(
                CallLog.Calls.CACHED_NAME,
                CallLog.Calls.TYPE,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION
            )
            val sortOrder = "${CallLog.Calls.DATE} DESC"
            val cursor = context.contentResolver.query(uri, projection, null, null, sortOrder)

            cursor?.use {
                val nameIdx = it.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val typeIdx = it.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = it.getColumnIndex(CallLog.Calls.DATE)
                val durationIdx = it.getColumnIndex(CallLog.Calls.DURATION)

                var count = 0
                while (it.moveToNext() && count < 50) {
                    count++
                    val name = it.getString(nameIdx)
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
                        put("name", if (name.isNullOrEmpty()) JSONObject.NULL else name)
                        put("type", typeStr)
                        put("timestamp", date)
                        put("duration", duration)
                    }
                    callsArray.put(callObj)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to query call history: ${e.message}")
        }

        return JSONObject().apply {
            put("type", "sync.call_history")
            put("version", 1)
            put("calls", callsArray)
        }
    }

    /**
     * Returns a permission denied payload.
     */
    fun getPermissionDeniedPayload(): JSONObject {
        return JSONObject().apply {
            put("type", "call_history.permission_denied")
            put("version", 1)
        }
    }
}
