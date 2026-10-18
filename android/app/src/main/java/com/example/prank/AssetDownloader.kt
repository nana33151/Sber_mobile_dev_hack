package com.example.prank

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class AssetDownloader(
    private val context: Context,
    private val manifest: Manifest,
) {
    private val rootDir = File(context.filesDir, "prank_cache")

    suspend fun updateIfNeeded(): Boolean = withContext(Dispatchers.IO) {
        val baseUrl = manifest.cdnBaseUrl ?: return@withContext false

        val remoteManifest = downloadJson("$baseUrl/manifest.json") ?: run {
            Log.d("AssetDownloader", "remote manifest unreachable")
            return@withContext false
        }
        val remoteVersion = remoteManifest.optString("currentVersion", "")
            .ifBlank { remoteManifest.optJSONObject("cdn")?.optString("currentVersion", "") ?: "" }
        if (remoteVersion.isBlank()) {
            Log.w("AssetDownloader", "remote manifest has no currentVersion")
            return@withContext false
        }

        val currentLatest = rootDir.listFiles()
            ?.filter { it.isDirectory && it.name.startsWith("v") }
            ?.maxByOrNull { it.name.removePrefix("v").toIntOrNull() ?: 0 }
            ?.name

        if (currentLatest == "v$remoteVersion") {
            Log.d("AssetDownloader", "up to date at v$remoteVersion")
            return@withContext false
        }

        val tmpDir = File(rootDir, "v${remoteVersion}.tmp")
        tmpDir.deleteRecursively()
        tmpDir.mkdirs()

        try {
            File(tmpDir, "manifest.json").writeText(remoteManifest.toString())

            val atlasFiles = mutableSetOf<String>()
            remoteManifest.optJSONObject("variants")?.let { v ->
                v.keys().forEach { k -> atlasFiles.add(v.getJSONObject(k).getString("atlas")) }
            }
            if (atlasFiles.isEmpty()) atlasFiles.add("atlas.json")

            val pngFiles = mutableSetOf<String>()
            for (atlasName in atlasFiles) {
                val atlasText = downloadText("$baseUrl/$atlasName") ?: return@withContext false
                File(tmpDir, atlasName).writeText(atlasText)
                JSONObject(atlasText).let { root ->
                    listOf("catStates", "catDance", "yarnVariants").forEach { key ->
                        pngFiles.add(root.getJSONObject(key).getString("image"))
                    }
                }
            }

            for (png in pngFiles) {
                if (!downloadToFile("$baseUrl/$png", File(tmpDir, png))) {
                    Log.w("AssetDownloader", "skip $png (network fail)")
                    return@withContext false
                }
            }

            val finalDir = File(rootDir, "v$remoteVersion")
            finalDir.deleteRecursively()
            if (!tmpDir.renameTo(finalDir)) {
                Log.e("AssetDownloader", "rename failed")
                return@withContext false
            }

            rootDir.listFiles()?.filter {
                it.isDirectory && it.name.startsWith("v") && it.name != "v$remoteVersion"
            }?.forEach { it.deleteRecursively() }

            Log.d("AssetDownloader", "updated to v$remoteVersion")
            true
        } catch (t: Throwable) {
            Log.e("AssetDownloader", "update failed", t)
            tmpDir.deleteRecursively()
            false
        }
    }

    private fun downloadJson(path: String): JSONObject? =
        downloadText(path)?.let { JSONObject(it) }

    private fun downloadText(path: String): String? = try {
        val conn = (URL(path).openConnection() as HttpURLConnection).apply {
            connectTimeout = 5000; readTimeout = 10000
        }
        conn.inputStream.bufferedReader().use { it.readText() }
            .also { conn.disconnect() }
    } catch (t: Throwable) {
        Log.w("AssetDownloader", "GET $path failed: ${t.message}"); null
    }

    private fun downloadToFile(url: String, target: File): Boolean = try {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 5000; readTimeout = 15000
        }
        conn.inputStream.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        }
        conn.disconnect()
        true
    } catch (t: Throwable) {
        Log.w("AssetDownloader", "GET $url failed: ${t.message}"); false
    }
}
