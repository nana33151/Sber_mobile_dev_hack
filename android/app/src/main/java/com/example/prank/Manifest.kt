package com.example.prank

import org.json.JSONObject

data class Manifest(
    val defaultVariant: String,
    val variants: Map<String, String>,   // variant -> atlas file name
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
                variants = variants,
                cdnBaseUrl = cdn?.optString("baseUrl")?.takeIf { it.isNotBlank() },
                cdnVersion = cdn?.optString("currentVersion")?.takeIf { it.isNotBlank() },
            )
        }

        /** Выбор variant по дате (для демо — зима/лето). */
        fun pickVariant(manifest: Manifest): String {
            val month = java.util.Calendar.getInstance().get(java.util.Calendar.MONTH) + 1
            return when {
                month in listOf(12, 1, 2) && manifest.variants.containsKey("winter") -> "winter"
                else -> manifest.defaultVariant
            }
        }
    }
}
