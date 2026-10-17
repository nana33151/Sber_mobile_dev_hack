package com.example.prank

import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.view.Gravity
import android.view.WindowManager
import android.widget.FrameLayout
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch

/**
 * Overlay-обёртка над WebView + PrankEngine + TiltForwarder.
 *
 * Отвечает ТОЛЬКО за lifecycle:
 *   - create WebView, addView в WindowManager
 *   - загрузка движка, init, отложенный show до готовности страницы
 *   - переключение alpha на Shown
 *   - destroy WebView + removeView + stop TiltForwarder
 *
 * НЕ решает:
 *   - когда показать (это триггер в host)
 *   - какой payload (это PrankPresets / host)
 *   - когда закрыть (это exit-policy в host)
 *
 * Один экземпляр = один показ. Хочешь ещё раз — создавай новый.
 */
class PrankOverlay(
    private val context: Context,
    private val windowManager: WindowManager,
    private val engineAssetPath: String = "prank_engine",
) {
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private val _events = MutableSharedFlow<PrankEvent>(
        replay = 8,
        extraBufferCapacity = 8,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val events: SharedFlow<PrankEvent> = _events.asSharedFlow()

    private var container: FrameLayout? = null
    private var webView: PrankWebView? = null
    private var engine: PrankEngine? = null
    private var tiltForwarder: TiltForwarder? = null

    private var pageReady = false
    private var pendingPayload: String? = null
    private var attached = false

    val isAttached: Boolean get() = attached

    fun attach() {
        if (attached) return
        attached = true

        val web = PrankWebView(context).apply { alpha = 0f }
        val eng = PrankEngine(web, scope)
        webView = web
        engine = eng

        val frame = FrameLayout(context).apply {
            addView(
                web,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        container = frame

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            flags,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }
        windowManager.addView(frame, lp)

        tiltForwarder = TiltForwarder(context, web).also { it.start() }

        web.onEnginePageFinished = {
            pageReady = true
            eng.init("""{"version":"1","enabled":true}""")
            pendingPayload?.let {
                pendingPayload = null
                eng.show(it)
            }
        }

        // Переключаем alpha только на Shown — Error/Hidden оставляем host'у
        scope.launch {
            eng.events.collect { event ->
                if (event is PrankEvent.Shown) web.alpha = 1f
                _events.emit(event)
            }
        }

        web.loadEngine(engineAssetPath)
    }

    fun show(payloadJson: String) {
        if (!attached) attach()
        if (pageReady) {
            engine?.show(payloadJson)
        } else {
            pendingPayload = payloadJson
        }
    }

    fun hide(reason: String = "manual") {
        engine?.hide(reason)
    }

    fun detach() {
        if (!attached) return
        attached = false

        tiltForwarder?.stop()
        tiltForwarder = null

        val wv = webView
        val ov = container
        webView = null
        container = null
        engine = null
        pageReady = false
        pendingPayload = null

        // destroy() до removeView() — иначе Chromium успевает ругнуться в лог
        try { wv?.destroy() } catch (_: Throwable) {}
        try { if (ov != null) windowManager.removeView(ov) } catch (_: Throwable) {}

        scope.cancel()
    }
}
