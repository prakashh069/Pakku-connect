package com.connecto.app

import android.app.Service
import android.content.Intent
import android.net.Uri
import android.os.IBinder
import android.provider.OpenableColumns
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.util.UUID

class FileTransferService : Service() {
    private val TAG = "FileTransferService"
    private val transferMutex = Mutex()
    private var pendingTransfers = 0
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private lateinit var transport: FileTransferTransport
    
    private var currentTransferId: String? = null
    
    private var readyJob: CompletableJob? = null
    private var ackJob: CompletableJob? = null
    private var completeJob: CompletableJob? = null
    private var transferResultReported = false

    override fun onCreate() {
        super.onCreate()
        Log.d("FileTransfer", "[PHASE7] SERVICE CREATED")
        transport = FileTransferTransport(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY

        Log.d("FileTransfer", "[FT-SERVICE] started")
        Log.d("FileTransfer", "[PHASE7] ON START COMMAND")

        val type = intent.type
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        
        val batchId = intent.getStringExtra("batchId")
        val batchCount = intent.getIntExtra("batchCount", -1).takeIf { it != -1 }
        val batchIndex = intent.getIntExtra("batchIndex", -1).takeIf { it != -1 }
        val batchTotal = intent.getIntExtra("batchTotal", -1).takeIf { it != -1 }
        val isBatchedZip = intent.getBooleanExtra("isBatchedZip", false)
        
        if (uri != null && type != null) {
            pendingTransfers++
            serviceScope.launch {
                try {
                    transferMutex.withLock {
                        Log.d("FileTransfer", "[PHASE8] STARTING queued transfer")
                        transferResultReported = false
                        handleTransfer(uri, type, batchId, batchCount, batchIndex, batchTotal, isBatchedZip)
                    }
                } finally {
                    pendingTransfers--
                    if (pendingTransfers <= 0) {
                        Log.d("FileTransfer", "[PHASE8] All transfers complete, stopping service")
                        stopSelf()
                    }
                }
            }
        } else {
            if (pendingTransfers <= 0) {
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    private suspend fun handleTransfer(uri: Uri, mimeType: String, batchId: String?, batchCount: Int?, batchIndex: Int?, batchTotal: Int?, isBatchedZip: Boolean) {
        currentTransferId = UUID.randomUUID().toString()
        val tempFile = java.io.File(cacheDir, "transfer_${currentTransferId}.tmp")

        try {
            Log.d("FileTransfer", "[PHASE7] PROCESSING URI: $uri")
            Log.d("FileTransfer", "[PHASE7] TRANSFER STARTED: $mimeType")
            Log.d("FileTransfer", "[FT-SERVICE] opening URI")
            var (filename, size) = getFileInfo(uri)
            Log.d("FileTransfer", "[PHASE7] FILE NAME: $filename")
            Log.d("FileTransfer", "[PHASE7] FILE SIZE: $size")
            
            if (filename == null) {
                val ext = if (mimeType.contains("image")) "jpg" else if (mimeType.contains("video")) "mp4" else "dat"
                filename = "shared_file_${System.currentTimeMillis()}.$ext"
            }

            Log.d(TAG, "Copying to cache to preserve read access...")
            contentResolver.openInputStream(uri)?.use { input ->
                tempFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            } ?: throw Exception("Cannot open stream for copying")

            if (size == null || size <= 0L) {
                size = tempFile.length()
            }

            if (size > 500 * 1024 * 1024) throw Exception("File too large (>500MB)")
            
            val totalChunks = Math.ceil(size.toDouble() / ChunkEngine.CHUNK_SIZE).toInt()

            Log.d(TAG, "Calculating SHA256...")
            val sha256 = tempFile.inputStream().use { 
                ChunkEngine.computeSha256(it) 
            }
            Log.d("FileTransfer", "[FT-SERVICE] SHA256 complete")
            Log.d("FileTransfer", "[PHASE7] SHA256 completed")

            transport.startListening { msg -> handleMessage(msg) }

            // 2. Send Start
            Log.d("FileTransfer", "[FT-SERVICE] sending START")
            Log.d("FileTransfer", "[PHASE7] ABOUT TO SEND START")
            val startMsg = JSONObject().apply {
                put("type", "file.transfer.start")
                put("transferId", currentTransferId)
                put("name", filename)
                put("mime", mimeType)
                put("size", size)
                put("totalChunks", totalChunks)
                put("sha256", sha256)
                put("isBatchedZip", isBatchedZip)
                
                // Add batch metadata if present
                batchId?.let { put("batchId", it) }
                batchCount?.let { put("batchCount", it) }
                batchIndex?.let { put("batchIndex", it) }
                batchTotal?.let { put("batchTotal", it) }
            }
            readyJob = Job()
            transport.send(startMsg)
            Log.d("FileTransfer", "[PHASE7] START SENT TO TRANSPORT")

            // 3. Wait for Ready (30s timeout)
            Log.d("FileTransfer", "[FT-SERVICE] waiting for ready")
            Log.d("FileTransfer", "[PHASE7] Waiting for ready")
            withTimeout(30000) {
                readyJob?.join()
            }
            Log.d(TAG, "macOS ready handshake received, starting chunks")

            // 4. Send Chunks
            completeJob = Job() // Initialize early to prevent race condition if Mac replies instantly
            tempFile.inputStream().use { stream ->
                val chunks = ChunkEngine.chunkStream(stream)
                var chunkIndex = 0
                for (chunkPayload in chunks) {
                    val chunkFile = java.io.File(cacheDir, "connecto_transfer/${currentTransferId}/${chunkIndex}.chunk")
                    chunkFile.parentFile?.mkdirs()
                    chunkFile.writeText(chunkPayload)
                    
                    Log.d("FileTransfer", "[PHASE7] Chunk written to cache: ${chunkFile.absolutePath}")
                    Log.d("FileTransfer", "[PHASE7] Sending chunk $chunkIndex")
                    
                    ackJob = Job()
                    transport.sendChunkReference(
                        currentTransferId!!,
                        chunkIndex,
                        totalChunks,
                        chunkFile.absolutePath
                    )
                    Log.d("FileTransfer", "[PHASE7] Chunk reference sent")

                    // Wait for ACK (30s timeout)
                    withTimeout(30000) {
                        ackJob?.join()
                    }
                    if (chunkFile.exists()) {
                        chunkFile.delete()
                        Log.d("FileTransfer", "[PHASE7] Chunk deleted")
                        Log.d("FileTransfer", "[PHASE7] Chunk cleanup completed")
                    }
                    chunkIndex++
                }
            }
            
            Log.d("FileTransfer", "[PHASE7] FINAL CHUNKS SENT")
            Log.d("FileTransfer", "[PHASE7] WAITING FOR COMPLETE SIGNAL")
            
            withTimeout(60000) {
                completeJob?.join()
            }

        } catch (e: TimeoutCancellationException) {
            if (completeJob != null && completeJob?.isCompleted == false) {
                Log.e("FileTransfer", "[PHASE7] COMPLETE SIGNAL TIMEOUT")
            }
            Log.e("FileTransfer", "Transfer failed", e)
            sendError("timeout")
            cleanupAndStop()
        } catch (e: Exception) {
            android.util.Log.e("FileTransfer", "Transfer failed", e)
        } finally {
            if (!transferResultReported) {
                sendError("write_failure")
            }
            cleanupAndStop()
        }
    }

    private fun handleMessage(json: JSONObject) {
        val type = json.optString("type")
        val transferId = json.optString("transferId")
        
        if (transferId != currentTransferId) return

        when (type) {
            "file.transfer.ready" -> {
                Log.d("FileTransfer", "[PHASE7] READY RECEIVED")
                readyJob?.complete()
            }
            "file.transfer.chunk_ack" -> {
                ackJob?.complete()
            }
            "file.transfer.complete" -> {
                Log.d("FileTransfer", "[PHASE7] COMPLETE SIGNAL RECEIVED")
                val match = json.optBoolean("sha256Match", false)
                if (!match) Log.e(TAG, "SHA256 mismatch reported by macOS")
                
                synchronized(this) {
                    if (!transferResultReported) {
                        transferResultReported = true
                        TransferQueueManager.onTransferComplete(this, true)
                    }
                }
                completeJob?.complete()
            }
            "file.transfer.error", "file.transfer.cancel" -> {
                readyJob?.cancel()
                ackJob?.cancel()
                completeJob?.cancel()
            }
        }
    }

    private fun sendError(reason: String) {
        if (currentTransferId == null) return
        val err = JSONObject().apply {
            put("type", "file.transfer.error")
            put("transferId", currentTransferId)
            put("reason", reason)
        }
        transport.send(err)
    }

    private fun getFileInfo(uri: Uri): Pair<String?, Long?> {
        var name: String? = null
        var size: Long? = null
        
        if (uri.scheme == "file") {
            val file = java.io.File(uri.path ?: "")
            return Pair(file.name, file.length())
        }

        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex != -1) name = cursor.getString(nameIndex)
                if (sizeIndex != -1) size = cursor.getLong(sizeIndex)
            }
        }
        return Pair(name, size)
    }

    private fun validateMime(filename: String, mime: String): Boolean {
        return true // Mac UI is robust enough to handle any file, no need to strictly block on Android side
    }

    private fun cleanupAndStop(success: Boolean = false) {
        var shouldReport = false
        Log.d("FileTransfer", "[PHASE7] ENTERING CLEANUP. Thread=${Thread.currentThread().id}, success=$success")
        synchronized(this) {
            Log.d("FileTransfer", "[PHASE7] INSIDE SYNC. transferResultReported=$transferResultReported")
            if (!transferResultReported) {
                transferResultReported = true
                shouldReport = true
            }
        }

        Log.d("FileTransfer", "[PHASE7] CLEANUP START. shouldReport=$shouldReport")
        
        if (shouldReport) {
            Log.d("FileTransfer", "[PHASE7] QUEUE CALLBACK SENT (success=$success)")
            TransferQueueManager.onTransferComplete(this, success)
        }

        transport.stopListening()
        
        // Cancel jobs for THIS transfer only, do not cancel the whole scope
        readyJob?.cancel()
        ackJob?.cancel()
        completeJob?.cancel()
        
        currentTransferId?.let { id ->
            try {
                val tempFile = java.io.File(cacheDir, "transfer_${id}.tmp")
                if (tempFile.exists()) tempFile.delete()
                
                val chunkDir = java.io.File(cacheDir, "connecto_transfer/$id")
                if (chunkDir.exists()) chunkDir.deleteRecursively()
            } catch (e: Exception) {
                Log.e("FileTransfer", "[PHASE8] Cleanup exception", e)
            }
        }

        currentTransferId = null
        Log.d("FileTransfer", "[PHASE8] cleanupAndStop finished for transfer")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
