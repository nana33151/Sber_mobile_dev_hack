package com.example.prank

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.os.SystemClock
import android.view.Choreographer
import android.view.View
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

@SuppressLint("ViewConstructor")
class PrankGameView(
    context: Context,
    private val spriteCache: SpriteCache,
) : View(context) {

    private val _events = MutableSharedFlow<PrankEvent>(
        replay = 8, extraBufferCapacity = 8,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val events: SharedFlow<PrankEvent> = _events.asSharedFlow()

    private val state = GameState()
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)

    private var atlas: Atlas? = null
    private var bmpCatStates: Bitmap? = null
    private var bmpCatDance: Bitmap? = null
    private var bmpYarn: Bitmap? = null

    private var running = false
    private var shownEmitted = false

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!running) return

            val nowMs = SystemClock.uptimeMillis()
            val result = state.update(nowMs)

            for (c in result.caught) _events.tryEmit(PrankEvent.Action("", "cat_caught"))
            if (result.danceComplete) {
                _events.tryEmit(PrankEvent.Action("", "game_won"))
                _events.tryEmit(PrankEvent.Hidden("", "game_won"))
                running = false
                return
            }

            invalidate()
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    init {
        setBackgroundColor(Color.TRANSPARENT)
        setLayerType(LAYER_TYPE_HARDWARE, null)
    }

    fun setAtlas(atlas: Atlas) {
        this.atlas = atlas
        bmpCatStates = spriteCache.load(atlas.catStates.assetFile)
        bmpCatDance = spriteCache.load(atlas.catDance.assetFile)
        bmpYarn = spriteCache.load(atlas.yarnVariants.assetFile)
    }

    fun setTilt(beta: Float, gamma: Float) = state.setRawOrientation(beta, gamma)

    fun startGame() {
        shownEmitted = false
        state.startRandom()
        startLoop()
    }

    fun startFinalDance(durationMs: Long) {
        shownEmitted = false
        state.startFinalDance(durationMs)
        startLoop()
    }

    fun stop() {
        running = false
        Choreographer.getInstance().removeFrameCallback(frameCallback)
    }

    private fun startLoop() {
        if (running) return
        running = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (width == 0 || height == 0) return
        val atlas = atlas ?: return
        val sheetCats = bmpCatStates ?: return
        val sheetYarn = bmpYarn ?: return
        val sheetDance = bmpCatDance ?: sheetCats

        val W = width.toFloat()
        val H = height.toFloat()
        val layout = computeLayout(W, H, state.cats.size)
        val nowMs = SystemClock.uptimeMillis()

        for (y in state.yarns) {
            if (y.caught) continue
            val frames = atlas.yarnVariants.indexedFrames
            if (frames.isEmpty()) continue
            val frame = frames[y.variant % frames.size]
            drawSprite(canvas, sheetYarn, frame, y.x * W, y.y * H, layout.yarnHeight)
        }

        for (c in state.cats) {
            val frame: Frame
            val sheet: Bitmap
            if (state.isDancing) {
                val frames = atlas.catDance.indexedFrames
                if (frames.isEmpty()) continue
                frame = frames[state.danceFrameIndex(nowMs).coerceIn(0, frames.size - 1)]
                sheet = sheetDance
            } else {
                val key = when {
                    c.balls <= 0 -> "ready"
                    c.balls == 1 -> "oneBall"
                    else -> "twoBalls"
                }
                frame = atlas.catStates.namedFrames[key] ?: continue
                sheet = sheetCats
            }
            drawSprite(canvas, sheet, frame, c.x * W, c.y * H, layout.catHeight * c.scale)
        }

        if (!shownEmitted) {
            shownEmitted = true
            _events.tryEmit(PrankEvent.Shown(""))
        }
    }

    private fun drawSprite(
        canvas: Canvas, sheet: Bitmap, frame: Frame,
        cx: Float, cy: Float, height: Float,
    ) {
        val src = Rect(frame.x, frame.y, frame.x + frame.width, frame.y + frame.height)
        val aspect = frame.width.toFloat() / frame.height
        val w = height * aspect
        val dst = RectF(cx - w / 2f, cy - height / 2f, cx + w / 2f, cy + height / 2f)
        canvas.drawBitmap(sheet, src, dst, paint)
    }

    private data class Layout(val catHeight: Float, val yarnHeight: Float)

    private fun computeLayout(width: Float, height: Float, catCount: Int): Layout {
        val short = minOf(width, height)
        val columns = catCount.coerceIn(3, 4).toFloat()
        val catH = minOf(width / columns * 0.92f, height * 0.24f, short * 0.36f)
        val yarnH = minOf(short * 0.12f, height * 0.085f)
        return Layout(catH, yarnH)
    }
}
