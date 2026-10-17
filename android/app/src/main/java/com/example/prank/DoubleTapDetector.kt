package com.example.prank

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager

class DoubleTapDetector(
    private val context: Context,
    private val onDoubleTap: () -> Unit,
) {
    private val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var probe: View? = null
    private var lastTapMs = 0L
    private val windowMs = 350L

    // ── Режим 1: probe-окно 1×1, ловит ACTION_OUTSIDE ──
    // Нужен, когда оверлей NOT_TOUCHABLE: тачи уходят в приложение под ним,
    // а probe получает событие «тап произошёл вне меня».

    fun attachProbe() {
        if (probe != null) return

        val view = View(context).apply {
            setBackgroundColor(Color.TRANSPARENT)
            isClickable = true
        }
        view.setOnTouchListener { _, event ->
            if (event.actionMasked == MotionEvent.ACTION_OUTSIDE) {
                checkDoubleTap("probe", SystemClock.elapsedRealtime())
            }
            false
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val lp = WindowManager.LayoutParams(
            1, 1, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 0
        }

        try {
            wm.addView(view, lp)
            probe = view
            Log.d(TAG, "probe attached")
        } catch (t: Throwable) {
            Log.e(TAG, "probe addView failed", t)
        }
    }

    // ── Режим 2: прямой вызов из WebView.onTouchListener ──
    // Нужен, когда оверлей сам принимает тачи (passThroughTouches = false).

    fun registerDirectTap() {
        checkDoubleTap("direct", SystemClock.elapsedRealtime())
    }

    // ── Общая логика: два тапа с интервалом 50..350 мс = double tap ──

    private fun checkDoubleTap(source: String, now: Long) {
        val delta = now - lastTapMs
        if (delta in 50..windowMs) {
            lastTapMs = 0L
            Log.d(TAG, "double tap ($source, delta=${delta}ms)")
            onDoubleTap()
        } else {
            lastTapMs = now
        }
    }

    fun detach() {
        probe?.let { try { wm.removeView(it) } catch (_: Throwable) {} }
        probe = null
        lastTapMs = 0L
    }

    companion object {
        private const val TAG = "DoubleTapDetector"
    }
}
