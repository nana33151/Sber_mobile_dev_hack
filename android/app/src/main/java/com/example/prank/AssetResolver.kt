package com.example.prank

import android.content.Context
import android.util.Log
import java.io.File

/**
 * Решает, откуда читать ассет:
 *  1. disk (скачано с CDN, свежая версия)
 *  2. assets (bundled, всегда работает)
 */
class AssetResolver(
    context: Context,
    config: PrankConfig,
) {
    private val assetsSource = AssetsSource(context, "${config.assetPath}/assets")
    private val diskSource: DiskSource? = resolveDiskSource(context)

    private fun resolveDiskSource(context: Context): DiskSource? {
        val root = File(context.filesDir, "prank_cache")
        if (!root.exists() || !root.isDirectory) return null
        // ищем самую свежую версию: prank_cache/v<N>/...
        val latest = root.listFiles()
            ?.filter { it.isDirectory && it.name.startsWith("v") }
            ?.maxByOrNull { it.name.removePrefix("v").toIntOrNull() ?: 0 }
            ?: return null
        return if (latest.listFiles()?.isNotEmpty() == true) DiskSource(latest) else null
    }

    fun open(fileName: String): java.io.InputStream? {
        diskSource?.open(fileName)?.let { return it }
        return assetsSource.open(fileName)
    }

    fun exists(fileName: String): Boolean =
        (diskSource?.exists(fileName) == true) || assetsSource.exists(fileName)

    /** Для отладки: пишет в лог, откуда читается файл. */
    fun describe(fileName: String): String = when {
        diskSource?.exists(fileName) == true -> "disk"
        assetsSource.exists(fileName) -> "assets"
        else -> "missing"
    }
}
