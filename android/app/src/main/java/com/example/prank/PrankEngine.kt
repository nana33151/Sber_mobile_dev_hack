package com.example.prank

import android.util.Log
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
            PrankBridge { event, payload -> handleEvent(event, payload) },
            "AndroidBridge"
        )
    }

    fun init(configJson: String) {
        webView.evaluateJavascript("window.PrankBridge.init($configJson);", null)
    }

    fun show(payloadJson: String) {
        showTimeoutJob?.cancel()
        currentPrankId = try {
            JSONObject(payloadJson).optString("id").takeIf { it.isNotBlank() }
        } catch (_: Exception) { null }

        webView.evaluateJavascript("window.PrankBridge.show($payloadJson);", null)

        // Игра может идти долго — 5 минут с запасом
        showTimeoutJob = scope.launch {
            delay(5 * 60_000)
            Log.w("PrankEngine", "Native timeout: forcing hide")
            hide("timeout")
            _events.emit(PrankEvent.Error("TIMEOUT", "Prank did not complete in 5m"))
        }
    }

    fun hide(reason: String = "manual") {
        showTimeoutJob?.cancel()
        webView.evaluateJavascript("window.PrankBridge.hide(${JSONObject.quote(reason)});", null)
    }

    private fun handleEvent(event: String, payload: JSONObject) {
        // Движок эхо-ит payload_id, если его нет — берём из текущего show()
        val id = payload.optString("payload_id").ifBlank { currentPrankId ?: "" }
        when (event) {
            "shown" -> _events.tryEmit(PrankEvent.Shown(id))

            "hidden" -> {
                showTimeoutJob?.cancel()
                val reason = payload.optString("reason", "manual")
                _events.tryEmit(PrankEvent.Hidden(id, reason))
            }

            "action" -> {
                val action = payload.optString("action")
                _events.tryEmit(PrankEvent.Action(id, action))
                // Конец игры: закрываем WebView после танца (движок уже отждал dance)
                if (action == "game_won") {
                    Log.d("PrankEngine", "game_won → auto hide")
                    hide("game_won")
                }
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
