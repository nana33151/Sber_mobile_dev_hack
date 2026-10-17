package com.example.prank

import android.util.Log
import android.webkit.WebView
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import org.json.JSONObject

class PrankEngine(
    private val webView: PrankWebView,
    private val scope: CoroutineScope
) {
    private val _events = MutableSharedFlow<PrankEvent>(
    replay = 8,
    extraBufferCapacity = 8,
    onBufferOverflow = kotlinx.coroutines.channels.BufferOverflow.DROP_OLDEST
	)
    val events = _events.asSharedFlow()

    private var showTimeoutJob: Job? = null
    private var currentPrankId: String? = null

    init {
        webView.addJavascriptInterface(
            PrankBridge { event, payload ->
                handleEvent(event, payload)
            },
            "AndroidBridge"
        )
    }

    fun init(configJson: String) {
        // Передаём JSON как объект, а не строку
        val js = "window.PrankBridge.init($configJson);"
        webView.evaluateJavascript(js, null)
    }

    fun show(payloadJson: String) {
        showTimeoutJob?.cancel()
        currentPrankId = try {
            JSONObject(payloadJson).optString("id")
        } catch (e: Exception) {
            null
        }

        val js = "window.PrankBridge.show($payloadJson);"
        webView.evaluateJavascript(js, null)

        // Нативный таймаут: если за 10 с не пришло hidden — принудительно скрываем
        showTimeoutJob = scope.launch {
            delay(10_000)
            Log.w("PrankEngine", "Native timeout: forcing hide")
            hide()
            _events.emit(PrankEvent.Error("TIMEOUT", "Prank did not complete in 10s"))
        }
    }

    fun hide() {
        showTimeoutJob?.cancel()
        webView.evaluateJavascript("window.PrankBridge.hide();", null)
    }

    private fun handleEvent(event: String, payload: JSONObject) {
        when (event) {
            "shown" -> {
                val id = payload.optString("payload_id")
                _events.tryEmit(PrankEvent.Shown(id))
            }
            "hidden" -> {
                showTimeoutJob?.cancel()
                val id = payload.optString("payload_id")
                val reason = payload.optString("reason", "manual")
                _events.tryEmit(PrankEvent.Hidden(id, reason))
            }
            "action" -> {
                val id = payload.optString("payload_id")
                val action = payload.optString("action")
                _events.tryEmit(PrankEvent.Action(id, action))
            }
            "error" -> {
                showTimeoutJob?.cancel()
                val code = payload.optString("code", "INTERNAL")
                val message = payload.optString("message", "Unknown error")
                _events.tryEmit(PrankEvent.Error(code, message))
            }
            else -> Log.w("PrankEngine", "Unknown event: $event")
        }
    }
}
