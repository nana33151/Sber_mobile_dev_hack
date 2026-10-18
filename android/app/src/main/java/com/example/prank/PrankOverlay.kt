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
import kotlinx.coroutines.withContext
import org.json.JSONObject

class PrankOverlay(
    private val context: Context,
    private val windowManager: WindowManager,
    private val config: PrankConfig = PrankConfig(),
) {
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val spriteCache = SpriteCache(context, "${config.engineAssetPath}/assets")

    private val _events = MutableSharedFlow<PrankEvent>(
        replay = 8, extraBufferCapacity = 8,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val events: SharedFlow<PrankEvent> = _events.asSharedFlow()

    private var container: FrameLayout? = null
    private var gameView: PrankGameView? = null
    private var tiltForwarder: TiltForwarder? = null

    private var attached = false
    private var atlasLoaded = false
    private var pendingPayload: String? = null

    fun attach() {
        if (attached) return
        attached = true

        val gv = PrankGameView(context, spriteCache)
        gameView = gv

        val frame = FrameLayout(context).apply {
            addView(gv, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ))
        }
        container = frame

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val lp = WindowManager.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP or Gravity.START }

        windowManager.addView(frame, lp)

        tiltForwarder = TiltForwarder(context) { beta, gamma -> gv.setTilt(beta, gamma) }
            .also { it.start() }

        scope.launch {
            gv.events.collect { event ->
                if (event is PrankEvent.Shown) gv.alpha = 1f
                _events.emit(event)
            }
        }

        scope.launch {
            val atlas = withContext(Dispatchers.IO) {
                val path = "${config.engineAssetPath}/assets/atlas.json"
                val json = context.assets.open(path).bufferedReader().use { it.readText() }
                Atlas.parse(json)
            }
            gv.setAtlas(atlas)
            atlasLoaded = true
            pendingPayload?.let {
                pendingPayload = null
                startFromPayload(it)
            }
        }
    }

    fun show(payloadJson: String) {
        if (!attached) attach()
        if (atlasLoaded) startFromPayload(payloadJson)
        else pendingPayload = payloadJson
    }

    fun hide(reason: String = "manual") {
        gameView?.stop()
        _events.tryEmit(PrankEvent.Hidden("", reason))
    }

    fun detach() {
        if (!attached) return
        attached = false

        tiltForwarder?.stop()
        tiltForwarder = null

        val ov = container
        container = null
        gameView?.stop()
        gameView = null

        try { if (ov != null) windowManager.removeView(ov) } catch (_: Throwable) {}

        scope.cancel()
    }

    private fun startFromPayload(payloadJson: String) {
        val gv = gameView ?: return
        val json = try { JSONObject(payloadJson) } catch (_: Exception) { null }
        when (json?.optString("mode", "game") ?: "game") {
            "final_dance" -> {
                val durationMs = json?.optLong("duration_ms", 2200L) ?: 2200L
                gv.startFinalDance(durationMs)
            }
            else -> gv.startGame()
        }
    }
}
