package com.example.prank

import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.JavascriptInterface
import org.json.JSONObject

class PrankBridge(
    private val onEvent: (event: String, payload: JSONObject) -> Unit
) {
    @JavascriptInterface
    fun postMessage(jsonString: String) {
        try {
            val json = JSONObject(jsonString)
            val event = json.optString("event")
            val payload = json.optJSONObject("payload") ?: JSONObject()
            Handler(Looper.getMainLooper()).post {
                onEvent(event, payload)
            }
        } catch (e: Exception) {
            Log.e("PrankBridge", "Bad message: $jsonString", e)
        }
    }
}
