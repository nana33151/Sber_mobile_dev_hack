package com.example.prank

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import android.util.LruCache

/**
 * Кеш целых спрайт-листов (PNG) в памяти.
 * Singleton через companion-фабрику: переживает пересоздание PrankOverlay между shake'ами.
 * Кадры НЕ нарезаем — режем при рисовании (canvas.drawBitmap(sheet, srcRect, dstRect)).
 */
class SpriteCache private constructor(
    private val resolver: AssetResolver,
    maxBytes: Int,
) {
    private val cache = object : LruCache<String, Bitmap>(maxBytes) {
        override fun sizeOf(key: String, bitmap: Bitmap): Int = bitmap.byteCount
    }

    fun load(fileName: String): Bitmap? {
        cache.get(fileName)?.let { return it }
        return try {
            resolver.open(fileName)?.use { stream ->
                val bmp = BitmapFactory.decodeStream(
                    stream, null,
                    BitmapFactory.Options().apply {
                        inPreferredConfig = Bitmap.Config.ARGB_8888
                        inScaled = false
                    }
                )
                if (bmp != null) {
                    Log.d(
                        "SpriteCache",
                        "load $fileName from ${resolver.describe(fileName)} (${bmp.byteCount / 1024} KB)"
                    )
                    cache.put(fileName, bmp)
                }
                bmp
            }
        } catch (t: Throwable) {
            Log.e("SpriteCache", "load $fileName failed", t)
            null
        }
    }

    fun clear() = cache.evictAll()

    companion object {
        @Volatile
        private var instance: SpriteCache? = null

        fun get(context: Context, config: PrankConfig): SpriteCache {
            return instance ?: synchronized(this) {
                instance ?: SpriteCache(
                    resolver = AssetResolver(context.applicationContext, config),
                    maxBytes = (Runtime.getRuntime().maxMemory() / 8).toInt(),
                ).also { instance = it }
            }
        }

        fun clearIfNeeded() {
            instance?.clear()
        }
    }
}
