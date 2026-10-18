package com.example.prank

import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.util.Log
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
    private val spriteCache = SpriteCache.get(context, config)
    private val assetResolver = AssetResolver(context, config)

    private val _events = MutableSharedFlow<PrankEvent>(
        replay = 8,
        extraBufferCapacity = 8,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val events: SharedFlow<PrankEvent> = _events.asSharedFlow()

    private var container: FrameLayout? = null
    private var gameView: PrankGameView? = null
    private var tiltForwarder: TiltForwarder? = null

    private var attached = false
    private var atlasLoaded = false
    private var pendingPayload: String? = null
    private var manifest: Manifest? = null

    fun attach() {
        if (attached) return
        attached = true

        val gv = PrankGameView(context, spriteCache).apply { alpha = 0f }
        gameView = gv

        val frame = FrameLayout(context).apply {
            addView(
                gv,
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
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            config.overlayFlags,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP or Gravity.START }

        try {
            windowManager.addView(frame, lp)
        } catch (t: Throwable) {
            Log.e("PrankOverlay", "addView failed", t)
            attached = false
            return
        }

        tiltForwarder = TiltForwarder(context) { beta, gamma -> gv.setTilt(beta, gamma) }
            .also { it.start() }

        scope.launch {
            gv.events.collect { event ->
                if (event is PrankEvent.Shown) gv.alpha = 1f
                _events.emit(event)
            }
        }

        scope.launch { loadAtlasAndStart() }
    }

    private suspend fun loadAtlasAndStart() {
        val localManifest = withContext(Dispatchers.IO) {
            try {
                assetResolver.open("manifest.json")
                    ?.bufferedReader()?.use { it.readText() }
                    ?.let { Manifest.parse(it) }
            } catch (t: Throwable) {
                Log.w("PrankOverlay", "manifest parse failed", t)
                null
            }
        }
        manifest = localManifest
        Log.d("PrankOverlay", "manifest loaded: variants=${localManifest?.variants?.keys}, cdn=${localManifest?.cdnBaseUrl}")

        if (localManifest?.cdnBaseUrl != null) {
            scope.launch(Dispatchers.IO) {
                try {
                    val updated = AssetDownloader(context, localManifest).updateIfNeeded()
                    if (updated) {
                        SpriteCache.clearIfNeeded()
                        Log.d("PrankOverlay", "assets updated via CDN, will apply on next shake")
                    }
                } catch (t: Throwable) {
                    Log.w("PrankOverlay", "CDN update failed", t)
                }
            }
        }

        val variant = localManifest?.let { Manifest.pickVariant(it) } ?: "default"
        val atlasFile = localManifest?.variants?.get(variant) ?: "atlas.json"
        Log.d("PrankOverlay", "loading atlas: variant=$variant file=$atlasFile")

        val atlas = withContext(Dispatchers.IO) {
            val text = assetResolver.open(atlasFile)?.bufferedReader()?.use { it.readText() }
            if (text == null) {
                Log.e("PrankOverlay", "atlas $atlasFile not found")
                null
            } else {
                try { Atlas.parse(text) }
                catch (t: Throwable) {
                    Log.e("PrankOverlay", "atlas parse failed", t); null
                }
            }
        }

        if (atlas == null) {
            _events.tryEmit(PrankEvent.Error("ATLAS_LOAD_FAILED", "atlas $atlasFile missing or malformed"))
            return
        }

        gameView?.setAtlas(atlas)
        atlasLoaded = true
        pendingPayload?.let { p ->
            pendingPayload = null
            startFromPayload(p)
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
        atlasLoaded = false
        pendingPayload = null

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
