package com.example.prank

import android.view.WindowManager

data class PrankConfig(
    // Имя папки в assets. Внутри ожидается:
    //   <assetPath>/assets/atlas.json
    //   <assetPath>/assets/manifest.json
    //   <assetPath>/assets/*.png
    val assetPath: String = "prank_engine",

    // Нативный watchdog: если hidden не пришёл за это время — принудительно гасим.
    val showTimeoutMs: Long = 5 * 60_000L,

    // Автоматически освобождать overlay по событию Hidden.
    val autoReleaseOnHidden: Boolean = true,

    // Флаги WindowManager для overlay-окна.
    val overlayFlags: Int =
        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
)
