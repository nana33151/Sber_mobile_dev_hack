package com.example.prank

import android.content.Context
import java.io.File
import java.io.InputStream

interface AssetSource {
    fun open(fileName: String): InputStream?
    fun exists(fileName: String): Boolean
}

class AssetsSource(
    private val context: Context,
    private val basePath: String,
) : AssetSource {
    override fun open(fileName: String): InputStream? = try {
        context.assets.open("$basePath/$fileName")
    } catch (_: Throwable) { null }

    override fun exists(fileName: String): Boolean =
        try { context.assets.open("$basePath/$fileName").close(); true }
        catch (_: Throwable) { false }
}

class DiskSource(private val dir: File) : AssetSource {
    override fun open(fileName: String): InputStream? = try {
        File(dir, fileName).takeIf { it.exists() }?.inputStream()
    } catch (_: Throwable) { null }

    override fun exists(fileName: String): Boolean = File(dir, fileName).exists()
}

class AssetResolver(
    context: Context,
    config: PrankConfig,
) {
    private val appContext = context.applicationContext
    private val assetsSource = AssetsSource(context, "${config.assetPath}/assets")
    private val cacheRoot = File(appContext.filesDir, "prank_cache")

    private fun currentDiskSource(): DiskSource? {
        val latest = cacheRoot.listFiles()
            ?.filter { it.isDirectory && it.name.startsWith("v") }
            ?.maxByOrNull { it.name.removePrefix("v").toIntOrNull() ?: 0 }
            ?: return null
        return if (latest.listFiles()?.isNotEmpty() == true) DiskSource(latest) else null
    }

    fun open(fileName: String): InputStream? {
        currentDiskSource()?.open(fileName)?.let { return it }
        return assetsSource.open(fileName)
    }

    fun exists(fileName: String): Boolean =
        currentDiskSource()?.exists(fileName) == true || assetsSource.exists(fileName)

    fun describe(fileName: String): String = when {
        currentDiskSource()?.exists(fileName) == true -> "disk"
        assetsSource.exists(fileName) -> "assets"
        else -> "missing"
    }
}
