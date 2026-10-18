package com.example.prank

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.atan2

class TiltForwarder(
    context: Context,
    private val onTilt: (beta: Float, gamma: Float) -> Unit,
) : SensorEventListener {

    private val sm = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accel: Sensor? = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private var sx = 0f; private var sy = 0f; private var sz = 0f

    fun start() { accel?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) } }
    fun stop() { sm.unregisterListener(this) }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
        val a = 0.15f
        sx += a * (event.values[0] - sx)
        sy += a * (event.values[1] - sy)
        sz += a * (event.values[2] - sz)

        val beta = Math.toDegrees(atan2(sy.toDouble(), sz.toDouble())).toFloat()
        val gamma = Math.toDegrees(atan2(-sx.toDouble(), sz.toDouble())).toFloat()
        onTilt(beta, gamma)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
