package com.example.prank

import android.view.WindowManager

data class PrankConfig(
    /** Имя папки в assets. Сейчас — "prank_engine", путь до index.html собирается сам. */
    val engineAssetPath: String = "prank_engine",

    /** Нативный watchdog — если `hidden` не пришёл за это время, принудительно гасим. */
    val showTimeoutMs: Long = 5 * 60_000L,

    /** Автоматически освобождать WebView по событию Hidden (обычный UX). */
    val autoReleaseOnHidden: Boolean = true,

    /** Флаги WindowManager для оверлея (по умолчанию — прозрачный, не-интерактивный). */
    val overlayFlags: Int =
        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
)
