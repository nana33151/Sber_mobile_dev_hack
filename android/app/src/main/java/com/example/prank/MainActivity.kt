package com.example.prank

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {

    private lateinit var status: TextView

    private val notifPerm = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* не критично */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 96, 48, 48)
        }
        status = TextView(this).apply { textSize = 16f }

        root.addView(status)
        root.addView(Button(this).apply {
            text = "1) Разрешить рисовать поверх других приложений"
            setOnClickListener { requestOverlayPermission() }
        })
        root.addView(Button(this).apply {
            text = "2) Включить триггер по тряске"
            setOnClickListener { armTrigger() }
        })
        root.addView(Button(this).apply {
            text = "Тест: показать игру сейчас"
            setOnClickListener { triggerNow() }
        })
        root.addView(Button(this).apply {
            text = "Остановить сервис"
            setOnClickListener {
                stopService(Intent(this@MainActivity, PrankTriggerService::class.java))
            }
        })
        root.addView(Button(this).apply {
   		 text = "Открыть демо-приложение"
   		 setOnClickListener {
        	 startActivity(Intent(this@MainActivity, DemoActivity::class.java))
   		 }
	})
        setContentView(root)

        if (Build.VERSION.SDK_INT >= 33) {
            notifPerm.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    override fun onResume() {
        super.onResume()
        refreshStatus()
    }

    private fun refreshStatus() {
        val overlay = Settings.canDrawOverlays(this)
        status.text = buildString {
            append("Prank control\n\n")
            append("Overlay: ").append(if (overlay) "OK" else "NOT GRANTED").append("\n")
            append("Shake trigger: ").append(if (overlay) "ready" else "needs overlay")
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName"),
                )
            )
        } else {
            refreshStatus()
        }
    }

    private fun armTrigger() {
        if (!Settings.canDrawOverlays(this)) { requestOverlayPermission(); return }
        ContextCompat.startForegroundService(
            this,
            Intent(this, PrankTriggerService::class.java).apply {
                action = PrankTriggerService.ACTION_START
            }
        )
    }

    private fun triggerNow() {
        if (!Settings.canDrawOverlays(this)) { requestOverlayPermission(); return }
        ContextCompat.startForegroundService(
            this,
            Intent(this, PrankTriggerService::class.java).apply {
                action = PrankTriggerService.ACTION_TRIGGER
            }
        )
    }
}
