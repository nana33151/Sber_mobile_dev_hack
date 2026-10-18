package com.example.prank

import org.json.JSONObject
import java.util.Calendar

data class Manifest(
    val defaultVariant: String,
    val activeVariant: String?,
    val variants: Map<String, String>,
    val cdnBaseUrl: String?,
    val cdnVersion: String?,
) {
    companion object {
        fun parse(json: String): Manifest {
            val root = JSONObject(json)
            val variantsNode = root.getJSONObject("variants")
            val variants = buildMap {
                variantsNode.keys().forEach { key ->
                    put(key, variantsNode.getJSONObject(key).getString("atlas"))
                }
            }
            val cdn = root.optJSONObject("cdn")
            return Manifest(
                defaultVariant = root.optString("defaultVariant", "default"),
                activeVariant = root.optString("activeVariant", "").takeIf { it.isNotBlank() },
                variants = variants,
                cdnBaseUrl = cdn?.optString("baseUrl")?.takeIf { it.isNotBlank() },
                cdnVersion = cdn?.optString("currentVersion")?.takeIf { it.isNotBlank() },
            )
        }

        fun pickVariant(manifest: Manifest): String {
            manifest.activeVariant
                ?.takeIf { manifest.variants.containsKey(it) }
                ?.let { return it }

            val month = Calendar.getInstance().get(Calendar.MONTH) + 1
            return when {
                month in listOf(12, 1, 2) && manifest.variants.containsKey("winter") -> "winter"
                else -> manifest.defaultVariant
            }
        }
    }
}
