package com.example.prank

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.sqrt

/**
 * Простой детектор тряски на акселерометре.
 * Сравниваем полное ускорение с порогом в единицах g, дебаунсим по времени.
 */
class ShakeDetector(
    context: Context,
    private val onShake: () -> Unit,
) : SensorEventListener {

    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    private var lastShakeMs = 0L
    private var isRunning = false

    /** 2.6g достаточно для тряски, но не срабатывает на шаг/машину. */
    var thresholdG: Float = 2.6f
    var cooldownMs: Long = 1200L

    fun start(): Boolean {
        if (isRunning) return true
        val sensor = accelerometer ?: return false
        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
        isRunning = true
        lastShakeMs = 0L
        return true
    }

    fun stop() {
        if (!isRunning) return
        sensorManager.unregisterListener(this)
        isRunning = false
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return

        val gx = event.values[0] / SensorManager.GRAVITY_EARTH
        val gy = event.values[1] / SensorManager.GRAVITY_EARTH
        val gz = event.values[2] / SensorManager.GRAVITY_EARTH
        val gForce = sqrt((gx * gx + gy * gy + gz * gz).toDouble()).toFloat()

        if (gForce > thresholdG) {
            val now = System.currentTimeMillis()
            if (now - lastShakeMs > cooldownMs) {
                lastShakeMs = now
                onShake()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
