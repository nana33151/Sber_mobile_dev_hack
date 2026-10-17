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
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

class PrankTriggerService : Service() {

    private lateinit var windowManager: WindowManager
    private lateinit var shakeDetector: ShakeDetector

    private var overlay: FrameLayout? = null
    private var webView: PrankWebView? = null
    private var engine: PrankEngine? = null
    private var tiltForwarder: TiltForwarder? = null
    private var tapDetector: DoubleTapDetector? = null

    private var isGameRunning = false

    /** Какой экран сейчас показывает DemoActivity (приходит broadcast'ом). */
    private var currentScreen: String = SCREEN_HOME

    /** Payload, выбранный в момент триггера — чтобы смена экрана во время
     *  загрузки WebView не влияла на уже запущенный пранк. */
    private var pendingPayload: String = GAME_PAYLOAD

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_SCREEN_CHANGED) return
            val screen = intent.getStringExtra(EXTRA_SCREEN) ?: return
            if (screen != currentScreen) {
                Log.d(TAG, "screen: $currentScreen → $screen")
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
            ACTION_STOP -> { stopSelf(); return START_NOT_STICKY }
            ACTION_TRIGGER -> if (Settings.canDrawOverlays(this)) triggerPrank()
        }
        return START_STICKY
    }

    private fun onShakeDetected() {
        if (isGameRunning) return
        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "No overlay permission — can't show prank")
            return
        }
        Log.d(TAG, "Shake → trigger")
        triggerPrank()
    }

    private fun triggerPrank() {
        if (isGameRunning) return
        isGameRunning = true

        // На экране оплаты — сразу финальный танец, иначе — обычная игра.
        pendingPayload = if (currentScreen == SCREEN_PAYMENT) {
            Log.d(TAG, "Trigger mode: FINAL_DANCE (screen=payment)")
            FINAL_DANCE_PAYLOAD
        } else {
            Log.d(TAG, "Trigger mode: GAME (screen=$currentScreen)")
            GAME_PAYLOAD
        }

        createOverlay()
    }

    private fun createOverlay() {
        if (overlay != null) return

        val web = PrankWebView(this).apply { alpha = 0f }
        val container = FrameLayout(this).apply {
            addView(
                web,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        // Тачи проходят сквозь оверлей в DemoActivity под ним
        val flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            flags,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }

        try {
            windowManager.addView(container, lp)
        } catch (t: Throwable) {
            Log.e(TAG, "addView failed", t)
            isGameRunning = false
            return
        }

        overlay = container
        webView = web

        tiltForwarder = TiltForwarder(this, web).also { it.start() }

        // Двойной тап: probe 1×1, ACTION_OUTSIDE ×2 → closeOverlay
        tapDetector = DoubleTapDetector(this) {
            Log.d(TAG, "double tap → close overlay")
            closeOverlay()
        }.also { it.attachProbe() }

        val eng = PrankEngine(web, scope)
        engine = eng

        // Захватываем payload в локальную переменную — если currentScreen
        // изменится во время загрузки страницы, это уже не повлияет.
        val payloadForThisRun = pendingPayload

        web.onEnginePageFinished = {
            eng.init("""{"version":"1","enabled":true}""")
            eng.show(payloadForThisRun)
        }

        scope.launch {
            eng.events.collect { event ->
                Log.d(TAG, "event: $event")
                when (event) {
                    is PrankEvent.Shown -> {
                        Log.d(TAG, "shown → alpha=1")
                        web.alpha = 1f
                    }
                    is PrankEvent.Hidden -> closeOverlay()
                    is PrankEvent.Error -> {
                        Log.e(TAG, "error ${event.code}: ${event.message}")
                        closeOverlay()
                    }
                    is PrankEvent.Action -> {
                        Log.d(TAG, "action: ${event.action}")
                        if (event.action == "close") closeOverlay()
                    }
                }
            }
        }

        web.loadEngine()
        Log.d(TAG, "Overlay added, loading engine")
    }

    private fun closeOverlay() {
        tapDetector?.detach()
        tapDetector = null
        tiltForwarder?.stop()
        tiltForwarder = null

        val wv = webView
        val ov = overlay
        webView = null
        overlay = null
        engine = null
        isGameRunning = false

        try { wv?.destroy() } catch (_: Throwable) {}
        try {
            if (ov != null) windowManager.removeView(ov)
        } catch (_: Throwable) {}

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

        // DemoActivity присылает это при каждой смене экрана (и в onResume).
        // Сервис теперь слушает broadcast, чтобы выбрать режим пранка.
        const val ACTION_SCREEN_CHANGED = "com.example.prank.SCREEN_CHANGED"
        const val EXTRA_SCREEN = "screen"

        private const val SCREEN_HOME    = "home"
        private const val SCREEN_PAYMENT = "payment"

        /** Обычная CSS-игра (котики ловят клубки). */
        private const val GAME_PAYLOAD =
            """{"version":"1","id":"prank_001","assets":{}}"""

        /** Только финальный танец — без геймплея. */
        private const val FINAL_DANCE_PAYLOAD =
            """{"version":"1","id":"prank_final_dance","mode":"final_dance","duration_ms":2200,"assets":{}}"""
    }
}
