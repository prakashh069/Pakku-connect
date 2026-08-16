package com.connecto.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

object TransferQueueManager {
    fun startQueue(context: Context, uris: ArrayList<Uri>, type: String?) {
        if (uris.isEmpty()) return

        if (uris.size == 1) {
            // Only 1 file, send normally
            val serviceIntent = Intent(context, FileTransferService::class.java).apply {
                this.action = Intent.ACTION_SEND
                this.type = type
                putExtra(Intent.EXTRA_STREAM, uris[0])
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startService(serviceIntent)
            return
        }

        // Multiple files -> zip them and send as single file
        Log.d("FileTransfer", "[PHASE7] ZIPPING ${uris.size} FILES")
        Log.d("FileTransfer", "[PHASE8] APPLICATION CONTEXT USED")
        val appContext = context.applicationContext
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val batchId = java.util.UUID.randomUUID().toString()
                val zipFile = File(appContext.cacheDir, "Shared_Images_$batchId.zip")
                if (zipFile.exists()) {
                    zipFile.delete()
                }

                ZipOutputStream(FileOutputStream(zipFile)).use { zos ->
                    val usedNames = mutableSetOf<String>()
                    for ((index, uri) in uris.withIndex()) {
                        var filename = getFilename(appContext, uri)
                        if (filename == null) {
                            val ext = if (type?.startsWith("image/") == true) "jpg" else "dat"
                            filename = "file_$index.$ext"
                        }
                        
                        var uniqueName = filename
                        var counter = 2
                        while (usedNames.contains(uniqueName)) {
                            val lastDot = filename.lastIndexOf('.')
                            if (lastDot > 0) {
                                val name = filename.substring(0, lastDot)
                                val ext = filename.substring(lastDot)
                                uniqueName = "${name}_$counter$ext"
                            } else {
                                uniqueName = "${filename}_$counter"
                            }
                            counter++
                        }
                        usedNames.add(uniqueName)
                        
                        val entry = ZipEntry(uniqueName)
                        zos.putNextEntry(entry)
                        
                        appContext.contentResolver.openInputStream(uri)?.use { input ->
                            input.copyTo(zos)
                        }
                        zos.closeEntry()
                    }
                }
                
                Log.d("FileTransfer", "[PHASE7] ZIP COMPLETE: ${zipFile.absolutePath}")
                Log.d("FileTransfer", "[PHASE8] ZIP SIZE: ${zipFile.length()}")
                Log.d("FileTransfer", "[PHASE8] ZIP PATH: ${zipFile.absolutePath}")

                val zipUri = Uri.fromFile(zipFile)
                val serviceIntent = Intent(appContext, FileTransferService::class.java).apply {
                    this.action = Intent.ACTION_SEND
                    this.type = "application/zip"
                    putExtra(Intent.EXTRA_STREAM, zipUri)
                    putExtra("isBatchedZip", true)
                    putExtra("batchCount", uris.size)
                    putExtra("batchId", batchId)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                context.startService(serviceIntent)
                
            } catch (e: Exception) {
                Log.e("FileTransfer", "Error zipping files", e)
            }
        }
    }

    private fun getFilename(context: Context, uri: Uri): String? {
        var name: String? = null
        if (uri.scheme == "content") {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex != -1) {
                        name = cursor.getString(nameIndex)
                    }
                }
            }
        } else if (uri.scheme == "file") {
            name = File(uri.path ?: "").name
        }
        return name
    }

    fun onTransferComplete(context: Context, success: Boolean) {
        // No-op for the zip implementation, but keeping it for compatibility with FileTransferService cleanup
        Log.d("FileTransfer", "[PHASE7] TRANSFER COMPLETE CALLBACK (success=$success)")
    }
}
