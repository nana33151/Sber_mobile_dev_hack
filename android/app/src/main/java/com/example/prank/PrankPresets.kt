package com.example.prank

/**
 * Host-side реестр приколов. Единственное место, где живут payload'ы
 * и связь «экран → прикол». Движок про этот файл не знает.
 */
object PrankPresets {

    const val SCREEN_HOME    = "home"
    const val SCREEN_PAYMENT = "payment"
    const val SCREEN_PROFILE = "profile"

    private const val GAME_PAYLOAD =
        """{"version":"1","id":"prank_001"}"""

    private const val FINAL_DANCE_PAYLOAD =
        """{"version":"1","id":"prank_final_dance","mode":"final_dance","duration_ms":2200}"""

    fun payloadForScreen(screen: String): String = when (screen) {
        SCREEN_PAYMENT -> FINAL_DANCE_PAYLOAD
        else           -> GAME_PAYLOAD
    }
}
