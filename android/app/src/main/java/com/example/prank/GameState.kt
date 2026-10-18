package com.example.prank

import android.os.SystemClock
import kotlin.math.hypot
import kotlin.random.Random

class GameState {
    data class Cat(val id: String, var x: Float, var y: Float, var balls: Int, var scale: Float = 1f)
    data class Yarn(val id: String, var x: Float, var y: Float, var variant: Int, var caught: Boolean = false)
    data class CaughtEvent(val catId: String, val x: Float, val y: Float)
    data class UpdateResult(
        val caught: List<CaughtEvent> = emptyList(),
        val winStarted: Boolean = false,
        val danceComplete: Boolean = false,
    )

    val cats = mutableListOf<Cat>()
    val yarns = mutableListOf<Yarn>()

    private var tiltX = 0f
    private var tiltY = 0f
    private var isCalibrated = false
    private var calBeta = 0f
    private var calGamma = 0f

    var isPlaying = false
        private set
    var isDancing = false
        private set

    private var danceStartedAt = 0L
    private var danceDurationMs = 1600L

    fun startRandom() {
        cats.clear(); yarns.clear()
        isCalibrated = false
        tiltX = 0f; tiltY = 0f
        isDancing = false
        danceStartedAt = 0L

        val numCats = 3 + Random.nextInt(2) // 3..4
        repeat(numCats) { i ->
            var x: Float; var y: Float; var attempts = 0
            do {
                x = 0.15f + Random.nextFloat() * 0.7f
                y = 0.15f + Random.nextFloat() * 0.7f
                attempts++
            } while (cats.any { hypot((x - it.x).toDouble(), (y - it.y).toDouble()) < 0.34 } && attempts < 200)
            cats.add(Cat("cat-$i", x, y, 0))
        }

        repeat(numCats * 2) { i ->
            var x: Float; var y: Float; var attempts = 0
            do {
                x = 0.1f + Random.nextFloat() * 0.8f
                y = 0.1f + Random.nextFloat() * 0.8f
                attempts++
            } while (
                (cats.any { hypot((x - it.x).toDouble(), (y - it.y).toDouble()) < 0.18 } ||
                 yarns.any { hypot((x - it.x).toDouble(), (y - it.y).toDouble()) < 0.12 }) &&
                attempts < 200
            )
            yarns.add(Yarn("yarn-$i", x, y, Random.nextInt(8)))
        }

        isPlaying = true
    }

    fun startFinalDance(durationMs: Long) {
        cats.clear(); yarns.clear()
        cats.add(Cat("solo-cat", 0.5f, 0.5f, 2, 1.2f))
        isCalibrated = false
        tiltX = 0f; tiltY = 0f
        isPlaying = true
        isDancing = true
        danceStartedAt = SystemClock.uptimeMillis()
        danceDurationMs = durationMs.coerceAtLeast(1000L)
    }

    fun setRawOrientation(beta: Float, gamma: Float) {
        if (!isPlaying) return
        if (!isCalibrated) {
            calBeta = beta; calGamma = gamma
            isCalibrated = true
            return
        }
        tiltX = (gamma - calGamma) / 45f
        tiltY = (beta - calBeta) / 45f
    }

    fun update(nowMs: Long): UpdateResult {
        if (!isPlaying) return UpdateResult()

        if (isDancing) {
            if (nowMs - danceStartedAt >= danceDurationMs) {
                isPlaying = false
                isDancing = false
                return UpdateResult(danceComplete = true)
            }
            return UpdateResult()
        }

        for (y in yarns) {
            if (y.caught) continue
            y.x = (y.x + tiltX * 0.012f).coerceIn(0.05f, 0.95f)
            y.y = (y.y + tiltY * 0.012f).coerceIn(0.05f, 0.95f)
        }

        val caught = mutableListOf<CaughtEvent>()
        for (y in yarns) {
            if (y.caught) continue
            for (c in cats) {
                if (c.balls >= 2) continue
                val dx = y.x - c.x
                val dy = y.y - c.y
                if (dx * dx + dy * dy < 0.18f * 0.18f) {
                    y.caught = true
                    c.balls++
                    caught.add(CaughtEvent(c.id, y.x, y.y))
                    break
                }
            }
        }

        if (yarns.isNotEmpty() && yarns.all { it.caught }) {
            isDancing = true
            danceStartedAt = nowMs
            danceDurationMs = 1600L
            return UpdateResult(caught = caught, winStarted = true)
        }

        return UpdateResult(caught = caught)
    }

    fun danceFrameIndex(nowMs: Long): Int {
        if (!isDancing) return 0
        val p = ((nowMs - danceStartedAt).toFloat() / danceDurationMs).coerceIn(0f, 0.9999f)
        return (p * 4).toInt()
    }
}
