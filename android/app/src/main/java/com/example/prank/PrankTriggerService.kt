package com.example.prank

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

class PrankTriggerService : Service() {

    private lateinit var windowManager: WindowManager
    private lateinit var shakeDetector: ShakeDetector

    private var overlay: PrankOverlay? = null
    private var tapDetector: DoubleTapDetector? = null
    private var eventCollectJob: Job? = null

    private var isGameRunning = false
    private var currentScreen: String = SCREEN_HOME

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_SCREEN_CHANGED) return
            val screen = intent.getStringExtra(EXTRA_SCREEN) ?: return
            if (screen != currentScreen) {
                Log.d(TAG, "screen: $currentScreen -> $screen")
                currentScreen = screen
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        shakeDetector = ShakeDetector(this) { onShakeDetected() }

        val filter = IntentFilter(ACTION_SCREEN_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(screenReceiver, filter)
        }

        startAsForeground()
        if (!shakeDetector.start()) {
            Log.w(TAG, "Accelerometer missing — shake won't fire")
        }
        Log.d(TAG, "Service created, waiting for shake (screen=$currentScreen)")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP    -> { stopSelf(); return START_NOT_STICKY }
            ACTION_TRIGGER -> triggerPrank()
        }
        return START_STICKY
    }

    private fun onShakeDetected() {
        if (isGameRunning) return
        Log.d(TAG, "Shake → trigger")
        triggerPrank()
    }

    private fun triggerPrank() {
        if (isGameRunning) return
        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "No overlay permission — can't show prank")
            return
        }
        isGameRunning = true

        // HOST-политика: какой прикол на каком экране
        val payload = if (currentScreen == SCREEN_PAYMENT) {
            Log.d(TAG, "Trigger mode: FINAL_DANCE (screen=payment)")
            FINAL_DANCE_PAYLOAD
        } else {
            Log.d(TAG, "Trigger mode: GAME (screen=$currentScreen)")
            GAME_PAYLOAD
        }

        // HOST-политика: как закрывать (double-tap)
        tapDetector = DoubleTapDetector(this) {
            Log.d(TAG, "double tap → close overlay")
            closeOverlay()
        }.also { it.attachProbe() }

        // ENGINE: overlay создаётся один раз на показ, весь boilerplate внутри
        val ov = PrankOverlay(this, windowManager)
        overlay = ov

        // HOST-политика: как реагировать на события
        eventCollectJob = scope.launch {
            ov.events.collect { event ->
                Log.d(TAG, "event: $event")
                when (event) {
                    is PrankEvent.Shown  -> { /* alpha уже переключён в PrankOverlay */ }
                    is PrankEvent.Hidden -> closeOverlay()
                    is PrankEvent.Error  -> {
                        Log.e(TAG, "error ${event.code}: ${event.message}")
                        closeOverlay()
                    }
                    is PrankEvent.Action -> if (event.action == "close") closeOverlay()
                }
            }
        }

        ov.show(payload)
    }

    private fun closeOverlay() {
        eventCollectJob?.cancel()
        eventCollectJob = null

        tapDetector?.detach()
        tapDetector = null

        overlay?.detach()
        overlay = null

        isGameRunning = false
        Log.d(TAG, "Overlay removed, back to armed state")
    }

    override fun onDestroy() {
        try { unregisterReceiver(screenReceiver) } catch (_: Throwable) {}
        shakeDetector.stop()
        closeOverlay()
        scope.cancel()
        super.onDestroy()
    }

    private fun startAsForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Prank trigger", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val stopIntent = Intent(this, PrankTriggerService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val openPending = PendingIntent.getActivity(
            this, 2, Intent(this, DemoActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Prank armed")
            .setContentText("Shake your phone to start")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setOngoing(true)
            .setContentIntent(openPending)
            .addAction(0, "Stop", stopPending)
            .build()
    }

    companion object {
        private const val TAG = "PrankTriggerService"
        private const val NOTIF_ID = 1001
        private const val CHANNEL_ID = "prank_trigger"

        const val ACTION_START   = "com.example.prank.START"
        const val ACTION_STOP    = "com.example.prank.STOP"
        const val ACTION_TRIGGER = "com.example.prank.TRIGGER"

        const val ACTION_SCREEN_CHANGED = "com.example.prank.SCREEN_CHANGED"
        const val EXTRA_SCREEN = "screen"

        private const val SCREEN_HOME    = "home"
        private const val SCREEN_PAYMENT = "payment"

        private const val GAME_PAYLOAD =
            """{"version":"1","id":"prank_001"}"""

        private const val FINAL_DANCE_PAYLOAD =
            """{"version":"1","id":"prank_final_dance","mode":"final_dance","duration_ms":2200}"""
    }
}
