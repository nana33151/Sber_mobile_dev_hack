package com.example.prank

import android.content.Context
import java.io.File
import java.io.InputStream

/** Абстракция над источником байтов: assets или диск. */
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
