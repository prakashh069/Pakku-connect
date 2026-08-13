package com.connecto.app.benchmark

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.system.measureTimeMillis

/**
 * Benchmark Test for Android Share Pipeline.
 * 
 * Measures:
 * 1. Image Decode Latency
 * 2. PNG Encoding Latency (Lossless)
 * 3. JPEG Compression Latency (Binary Search Simulation)
 * 4. Base64 Encoding Latency
 * 5. Peak Memory Usage during pipeline
 */
class ShareBenchmarkTest {

    fun runBenchmarks(testImageFile: File) {
        println("=== Pakku Share Framework: Android Benchmarks ===")
        println("Target File: ${testImageFile.name} (${testImageFile.length() / 1024} KB)")

        val runtime = Runtime.getRuntime()
        runtime.gc()
        val startMemory = runtime.totalMemory() - runtime.freeMemory()

        // 1. Image Decode
        var bitmap: Bitmap? = null
        val decodeTime = measureTimeMillis {
            bitmap = BitmapFactory.decodeFile(testImageFile.absolutePath)
        }
        println("[Decode] BitmapFactory.decodeFile: ${decodeTime}ms")
        
        if (bitmap == null) {
            println("Failed to decode image. Aborting benchmarks.")
            return
        }

        val postDecodeMemory = runtime.totalMemory() - runtime.freeMemory()
        println("[Memory] Bitmap Memory Footprint: ${(postDecodeMemory - startMemory) / (1024 * 1024)} MB")

        // 2. PNG Encoding (Lossless)
        val pngStream = ByteArrayOutputStream()
        val pngTime = measureTimeMillis {
            bitmap!!.compress(Bitmap.CompressFormat.PNG, 100, pngStream)
        }
        val pngBytes = pngStream.toByteArray()
        println("[Encode] PNG Compress (100%): ${pngTime}ms -> ${pngBytes.size / 1024} KB")

        // 3. JPEG Binary Search Compression (Simulating PhoneStateService logic)
        // Target: <= 5MB
        val maxSizeBytes = 5 * 1024 * 1024
        var quality = 100
        var min = 30
        var max = 100
        var jpegBytes: ByteArray = ByteArray(0)
        var iterations = 0

        val jpegTime = measureTimeMillis {
            while (min <= max) {
                iterations++
                val stream = ByteArrayOutputStream()
                bitmap!!.compress(Bitmap.CompressFormat.JPEG, quality, stream)
                val currentBytes = stream.toByteArray()
                
                // Base64 expands by ~33%
                val estimatedBase64Size = (currentBytes.size * 1.37).toLong()
                
                if (estimatedBase64Size <= maxSizeBytes) {
                    jpegBytes = currentBytes
                    min = quality + 1 
                } else {
                    max = quality - 1 
                }
                quality = (min + max) / 2
                
                // Safety break matching production
                if (iterations >= 7) {
                    jpegBytes = currentBytes
                    break
                }
            }
        }
        println("[Compress] JPEG Binary Search (${iterations} iterations): ${jpegTime}ms -> ${jpegBytes.size / 1024} KB (Quality: $quality)")

        // 4. Base64 Encoding
        var base64String = ""
        val base64Time = measureTimeMillis {
            base64String = Base64.encodeToString(jpegBytes, Base64.NO_WRAP)
        }
        println("[Encode] Base64 Encoding: ${base64Time}ms -> ${base64String.length / 1024} KB payload")

        val peakMemory = runtime.totalMemory() - runtime.freeMemory()
        println("[Memory] Peak Pipeline Delta: ${(peakMemory - startMemory) / (1024 * 1024)} MB")
        println("=================================================")
        
        bitmap?.recycle()
    }
}
