package com.example.prank

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import android.util.LruCache

/**
 * Кеш целых спрайт-листов (PNG из assets).
 * Кадры НЕ нарезаем — режем при рисовании через canvas.drawBitmap(sheet, srcRect, dstRect).
 * Память: 1/8 от max heap (~32 MB на 256 MB heap), хватает на 3 листа.
 */
class SpriteCache(
    private val context: Context,
    private val basePath: String = "prank_engine/assets",
    maxBytes: Int = (Runtime.getRuntime().maxMemory() / 8).toInt(),
) {
    private val cache = object : LruCache<String, Bitmap>(maxBytes) {
        override fun sizeOf(key: String, bitmap: Bitmap): Int = bitmap.byteCount
    }

    fun load(fileName: String): Bitmap? {
        cache.get(fileName)?.let { return it }
        return try {
            context.assets.open("$basePath/$fileName").use { stream ->
                val bmp = BitmapFactory.decodeStream(
                    stream, null,
                    BitmapFactory.Options().apply {
                        inPreferredConfig = Bitmap.Config.ARGB_8888
                        inScaled = false
                    }
                ) ?: return null
                cache.put(fileName, bmp)
                bmp
            }
        } catch (t: Throwable) {
            Log.e("SpriteCache", "load $fileName failed", t)
            null
        }
    }

    fun clear() = cache.evictAll()
}
