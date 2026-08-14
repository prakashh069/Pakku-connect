package com.connecto.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.InputStream
import kotlin.math.max
import kotlin.math.roundToInt

object ImageCompressor {
    private const val TAG = "ImageCompressor"
    private const val MAX_DIMENSION = 1920 // 1080p equivalent bounding box
    private const val MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024 // 5MB limit
    
    fun compressAndStripExif(context: Context, uri: Uri): ByteArray? {
        var inputStream: InputStream? = null
        try {
            // 1. Get rotation from EXIF
            inputStream = context.contentResolver.openInputStream(uri) ?: return null
            val exif = ExifInterface(inputStream)
            val orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            inputStream.close()
            
            // 2. Read dimensions
            inputStream = context.contentResolver.openInputStream(uri) ?: return null
            val options = BitmapFactory.Options()
            options.inJustDecodeBounds = true
            BitmapFactory.decodeStream(inputStream, null, options)
            inputStream.close()
            
            // 3. Calculate downsampling to save memory
            options.inSampleSize = calculateInSampleSize(options, MAX_DIMENSION, MAX_DIMENSION)
            options.inJustDecodeBounds = false
            
            // 4. Decode the image (EXIF is fundamentally stripped here)
            inputStream = context.contentResolver.openInputStream(uri) ?: return null
            var bitmap = BitmapFactory.decodeStream(inputStream, null, options) ?: return null
            inputStream.close()
            
            // 5. Apply EXIF rotation to the Bitmap so it stays upright
            bitmap = rotateBitmap(bitmap, orientation)
            
            // 6. Scale if still too large
            bitmap = scaleBitmapDown(bitmap, MAX_DIMENSION)
            
            // 7. Compress to JPEG
            var quality = 90
            var outputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)
            
            // 8. Iterate to hit size target
            while (outputStream.toByteArray().size > MAX_FILE_SIZE_BYTES && quality > 10) {
                outputStream.reset()
                quality -= 15
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)
            }
            
            val finalBytes = outputStream.toByteArray()
            bitmap.recycle()
            outputStream.close()
            
            return finalBytes
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to compress image", e)
            return null
        } finally {
            try { inputStream?.close() } catch (e: Exception) {}
        }
    }

    private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        val (height: Int, width: Int) = options.outHeight to options.outWidth
        var inSampleSize = 1
        if (height > reqHeight || width > reqWidth) {
            val halfHeight: Int = height / 2
            val halfWidth: Int = width / 2
            while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }

    private fun rotateBitmap(bitmap: Bitmap, orientation: Int): Bitmap {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1.0f, 1.0f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> {
                matrix.preScale(1.0f, -1.0f)
                matrix.postRotate(180f)
            }
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.preScale(-1.0f, 1.0f)
                matrix.postRotate(90f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.preScale(-1.0f, 1.0f)
                matrix.postRotate(270f)
            }
            else -> return bitmap
        }
        return try {
            val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            if (rotated != bitmap) {
                bitmap.recycle()
            }
            rotated
        } catch (e: OutOfMemoryError) {
            bitmap
        }
    }
    
    private fun scaleBitmapDown(bitmap: Bitmap, maxDimension: Int): Bitmap {
        val maxDim = max(bitmap.width, bitmap.height)
        if (maxDim <= maxDimension) return bitmap
        
        val scale = maxDimension.toFloat() / maxDim
        val newWidth = (bitmap.width * scale).roundToInt()
        val newHeight = (bitmap.height * scale).roundToInt()
        
        return try {
            val scaled = Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
            if (scaled != bitmap) {
                bitmap.recycle()
            }
            scaled
        } catch (e: OutOfMemoryError) {
            bitmap
        }
    }
}
