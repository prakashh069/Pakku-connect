package com.pakku.pakku_connect

import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

data class ReplyData(
    val handle: String,
    val pendingIntent: PendingIntent,
    val remoteInputKey: String,
    val expirationTimestamp: Long,
    val packageName: String,
    val sessionId: String
)

object NotificationReplyManager {
    private const val TAG = "NotificationReplyManager"
    private const val MAX_HANDLES = 20
    private const val TTL_MS = 5 * 60 * 1000L // 5 minutes

    private val replyHandles = ConcurrentHashMap<String, ReplyData>()

    /**
     * Stores a reply handle.
     * Enforces the MAX_HANDLES limit and TTL.
     */
    fun storeHandle(
        pendingIntent: PendingIntent,
        remoteInputKey: String,
        packageName: String,
        sessionId: String
    ): String {
        cleanupExpired()

        if (replyHandles.size >= MAX_HANDLES) {
            // Remove the oldest handle if still over limit
            val oldest = replyHandles.values.minByOrNull { it.expirationTimestamp }
            if (oldest != null) {
                replyHandles.remove(oldest.handle)
                Log.d(TAG, "Removed oldest handle to stay within MAX_HANDLES")
            }
        }

        val handle = UUID.randomUUID().toString()
        val replyData = ReplyData(
            handle = handle,
            pendingIntent = pendingIntent,
            remoteInputKey = remoteInputKey,
            expirationTimestamp = System.currentTimeMillis() + TTL_MS,
            packageName = packageName,
            sessionId = sessionId
        )

        replyHandles[handle] = replyData
        Log.d(TAG, "Stored reply handle for package: $packageName, session: $sessionId")
        return handle
    }

    /**
     * Cleans up expired handles.
     */
    private fun cleanupExpired() {
        val now = System.currentTimeMillis()
        val expiredKeys = replyHandles.filterValues { it.expirationTimestamp <= now }.keys
        expiredKeys.forEach {
            replyHandles.remove(it)
        }
        if (expiredKeys.isNotEmpty()) {
            Log.d(TAG, "Cleaned up ${expiredKeys.size} expired handles")
        }
    }

    /**
     * Executes the reply, verifying all constraints.
     */
    fun executeReply(
        context: Context,
        handle: String,
        replyText: String,
        currentSessionId: String
    ): Boolean {
        cleanupExpired()

        val replyData = replyHandles[handle]
        if (replyData == null) {
            Log.w(TAG, "Reply rejected: handle does not exist or expired")
            return false
        }

        // 1. One-time use: immediately remove the handle
        replyHandles.remove(handle)

        // 2. Validate session
        if (replyData.sessionId != currentSessionId) {
            Log.w(TAG, "Reply rejected: session mismatch")
            return false
        }

        // 3. Validate expiration (double check)
        if (System.currentTimeMillis() > replyData.expirationTimestamp) {
            Log.w(TAG, "Reply rejected: handle expired")
            return false
        }
        
        Log.d(TAG, "Validation passed. Executing reply for package: ${replyData.packageName}")

        return try {
            val intent = Intent()
            val bundle = Bundle()
            bundle.putCharSequence(replyData.remoteInputKey, replyText)
            RemoteInput.addResultsToIntent(
                arrayOf(RemoteInput.Builder(replyData.remoteInputKey).build()),
                intent,
                bundle
            )

            replyData.pendingIntent.send(context, 0, intent)
            Log.d(TAG, "Reply executed successfully")
            true
        } catch (e: PendingIntent.CanceledException) {
            Log.e(TAG, "Failed to execute reply: PendingIntent canceled", e)
            false
        } catch (e: Exception) {
            Log.e(TAG, "Failed to execute reply: Exception", e)
            false
        }
    }
}
