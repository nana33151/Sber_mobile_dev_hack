package com.example.prank

import android.app.Activity
import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.util.Log
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch

/**
 * Единственная точка входа для host-приложения.
 *
 * Не знает ничего про конкретные приколы и экраны. Работает в двух режимах:
 *
 *  Overlay (поверх всего):
 *    linker.attachToOverlay(windowManager)
 *
 *  Activity (внутри своего экрана):
 *    linker.attachToActivity(activity, container)
 *
 * Дальше — одинаково:
 *    linker.show(payloadJson)
 *    linker.events.collect { event -> ... }
 *    linker.release()  // или linker.releaseAll()
 */
class PrankLinker(
    private val context: Context,
    private val config: PrankConfig = PrankConfig(),
) {
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private val _events = MutableSharedFlow<PrankEvent>(
        replay = 8,
        extraBufferCapacity = 8,
        onBufferOverflow = kotlinx.coroutines.channels.BufferOverflow.DROP_OLDEST,
    )
    val events: SharedFlow<PrankEvent> = _events.asSharedFlow()

    private var attachedTo: AttachTarget? = null
    private var webView: PrankWebView? = null
    private var engine: PrankEngine? = null
    private var overlayContainer: FrameLayout? = null
    private var tiltForwarder: TiltForwarder? = null

    private var engineReady = false
    private var pendingPayload: String? = null

    sealed class AttachTarget {
        data class Overlay(val wm: WindowManager) : AttachTarget()
        data class InView(val container: ViewGroup) : AttachTarget()
    }

    fun attachToOverlay(windowManager: WindowManager): PrankLinker {
        attachedTo = AttachTarget.Overlay(windowManager)
        return this
    }

    fun attachToActivity(activity: Activity, container: ViewGroup): PrankLinker {
        attachedTo = AttachTarget.InView(container)
        return this
    }

    fun show(payloadJson: String) {
        val target = attachedTo
            ?: error("PrankLinker: attachTo{Overlay,Activity}() must be called before show()")

        // Уже показан — просто перезапускаем в том же WebView
        webView?.let { web ->
            engine?.let { eng ->
                if (engineReady) { eng.show(payloadJson); return }
                pendingPayload = payloadJson
                return@let
            }
        }

        // Первый show — создаём WebView + Engine
        val web = createWebView(target)
        val eng = PrankEngine(web, scope, config)
        webView = web
        engine = eng

        tiltForwarder = TiltForwarder(context, web).also { it.start() }

        scope.launch {
            eng.events.collect { event ->
                when (event) {
                    is PrankEvent.Shown  -> web.alpha = 1f
                    is PrankEvent.Hidden -> {
                        web.alpha = 0f
                        if (config.autoReleaseOnHidden) release()
                    }
                    is PrankEvent.Error  -> {
                        web.alpha = 0f
                        if (config.autoReleaseOnHidden) release()
                    }
                    is PrankEvent.Action -> { /* host decides */ }
                }
                _events.emit(event)
            }
        }

        web.onEnginePageFinished = {
            engineReady = true
            eng.init("""{"version":"1","enabled":true}""")
            pendingPayload?.let { eng.show(it); pendingPayload = null }
        }
        web.loadEngine(config.engineAssetPath)
    }

    fun hide(reason: String = "manual") {
        pendingPayload = null
        engine?.hide(reason)
    }

    /** Снять WebView с экрана, освободить ресурсы. Линкер остаётся переиспользуемым. */
    fun release() {
        tiltForwarder?.stop()
        tiltForwarder = null

        val wv = webView
        val ov = overlayContainer
        webView = null
        overlayContainer = null
        engine = null
        engineReady = false
        pendingPayload = null

        try { wv?.destroy() } catch (_: Throwable) {}

        when (val t = attachedTo) {
            is AttachTarget.Overlay -> try {
                ov?.let { t.wm.removeView(it) }
            } catch (_: Throwable) {}
            is AttachTarget.InView -> try {
                ov?.let { t.container.removeView(it) }
            } catch (_: Throwable) {}
            null -> {}
        }
    }

    /** Полный shutdown: release + cancel scope + detach. */
    fun releaseAll() {
        release()
        scope.cancel()
        attachedTo = null
    }

    private fun createWebView(target: AttachTarget): PrankWebView {
        val web = PrankWebView(context).apply { alpha = 0f }

        val container = FrameLayout(context).apply {
            addView(web, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ))
        }
        overlayContainer = container

        when (target) {
            is AttachTarget.Overlay -> {
                val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

                val lp = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    type,
                    config.overlayFlags,
                    PixelFormat.TRANSLUCENT,
                ).apply { gravity = Gravity.TOP or Gravity.START }
                target.wm.addView(container, lp)
            }
            is AttachTarget.InView -> {
                target.container.addView(container, ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ))
            }
        }
        return web
    }
}
