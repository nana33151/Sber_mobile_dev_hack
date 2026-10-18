package com.example.prank

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Скачивает ассеты с CDN в фоне. Атомарная запись через tmp-директорию.
 * Если что-то пошло не так — старая версия на диске остаётся, assets — fallback.
 */
class AssetDownloader(
    private val context: Context,
    private val manifest: Manifest,
) {
    private val rootDir = File(context.filesDir, "prank_cache")

    /**
     * Возвращает true, если удалось скачать новую версию и она встала на место.
     * true → следующий PrankOverlay.attach() будет читать с диска.
     */
    suspend fun updateIfNeeded(): Boolean = withContext(Dispatchers.IO) {
        val baseUrl = manifest.cdnBaseUrl ?: return@withContext false
        val remoteVersion = manifest.cdnVersion ?: return@withContext false

        val currentLatest = rootDir.listFiles()
            ?.filter { it.isDirectory && it.name.startsWith("v") }
            ?.maxByOrNull { it.name.removePrefix("v").toIntOrNull() ?: 0 }
            ?.name

        if (currentLatest == "v$remoteVersion") {
            Log.d("AssetDownloader", "already at v$remoteVersion, skip")
            return@withContext false
        }

        val tmpDir = File(rootDir, "v${remoteVersion}.tmp")
        tmpDir.deleteRecursively()
        tmpDir.mkdirs()

        try {
            // 1. Скачать манифест CDN: baseUrl/manifest.json
            val remoteManifest = downloadJson("$baseUrl/manifest.json")
                ?: return@withContext false

            // 2. Скачать все файлы, на которые он ссылается
            val filesToFetch = mutableSetOf("atlas.json")
            remoteManifest.getJSONObject("variants").let { v ->
                v.keys().forEach { k -> filesToFetch.add(v.getJSONObject(k).getString("atlas")) }
            }
            // + PNG: разбираем atlas → имена
            val atlasJson = downloadText("$baseUrl/atlas.json") ?: return@withContext false
            JSONObject(atlasJson).let { root ->
                listOf("catStates", "catDance", "yarnVariants").forEach { key ->
                    filesToFetch.add(root.getJSONObject(key).getString("image"))
                }
            }
            filesToFetch.forEach { name ->
                if (!downloadToFile("$baseUrl/$name", File(tmpDir, name))) {
                    Log.w("AssetDownloader", "skip $name (network fail)")
                    return@withContext false
                }
            }

            // 3. Атомарно поставить на место
            val finalDir = File(rootDir, "v$remoteVersion")
            finalDir.deleteRecursively()
            if (!tmpDir.renameTo(finalDir)) {
                Log.e("AssetDownloader", "rename failed")
                return@withContext false
            }

            // 4. Удалить старые версии (оставить только текущую)
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
