package com.connecto.app

import android.util.Base64
import java.io.InputStream
import java.security.MessageDigest

object ChunkEngine {
    const val CHUNK_SIZE = 256 * 1024 // 256 KB

    fun computeSha256(inputStream: InputStream): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(8192)
        var bytesRead: Int
        
        while (inputStream.read(buffer).also { bytesRead = it } != -1) {
            digest.update(buffer, 0, bytesRead)
        }
        
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun chunkStream(inputStream: InputStream): Sequence<String> {
        return sequence {
            val buffer = ByteArray(CHUNK_SIZE)
            var bytesRead: Int
            
            while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                if (bytesRead == CHUNK_SIZE) {
                    yield(Base64.encodeToString(buffer, Base64.NO_WRAP))
                } else {
                    val lastChunk = ByteArray(bytesRead)
                    System.arraycopy(buffer, 0, lastChunk, 0, bytesRead)
                    yield(Base64.encodeToString(lastChunk, Base64.NO_WRAP))
                }
            }
        }
    }
}
