package com.agrisense.app

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
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/** Foreground service that polls the API while the screen is on, so widgets update in near real time. */
class LiveService : Service() {
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    @Volatile private var screenOn = true

    private val tick = object : Runnable {
        override fun run() {
            if (!running || !screenOn) return
            try {
                Net.fetchAndStore(this@LiveService)
                Updater.onChanged(this@LiveService)
            } catch (e: Exception) {
                // keep polling
            }
            handler?.postDelayed(this, Live.intervalSec(this@LiveService) * 1000L)
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val h = handler ?: return
            when (intent.action) {
                Intent.ACTION_SCREEN_ON -> {
                    screenOn = true
                    h.removeCallbacks(tick)
                    h.post(tick)
                }
                Intent.ACTION_SCREEN_OFF -> {
                    screenOn = false
                    h.removeCallbacks(tick)
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val t = HandlerThread("agrisense-live")
        t.start()
        thread = t
        handler = Handler(t.looper)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Live.set(this, false, Live.intervalSec(this))
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                ServiceCompat.startForeground(this, NID, buildNotification(this), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NID, buildNotification(this))
            }
        } catch (e: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!running) {
            running = true
            try {
                ContextCompat.registerReceiver(
                    this, screenReceiver,
                    IntentFilter().apply {
                        addAction(Intent.ACTION_SCREEN_ON)
                        addAction(Intent.ACTION_SCREEN_OFF)
                    },
                    ContextCompat.RECEIVER_NOT_EXPORTED
                )
            } catch (e: Exception) {
                // already registered
            }
        }
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        screenOn = pm.isInteractive
        handler?.removeCallbacks(tick)
        if (screenOn) handler?.post(tick)
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        try {
            unregisterReceiver(screenReceiver)
        } catch (e: Exception) {
            // not registered
        }
        handler?.removeCallbacksAndMessages(null)
        thread?.quitSafely()
        super.onDestroy()
    }

    companion object {
        const val CH = "live"
        const val NID = 4201
        const val ACTION_STOP = "com.agrisense.app.STOP_LIVE"
        @Volatile var running = false

        fun start(ctx: Context) {
            try {
                ContextCompat.startForegroundService(ctx.applicationContext, Intent(ctx.applicationContext, LiveService::class.java))
            } catch (e: Exception) {
                // background start not allowed right now; the 15-minute worker still keeps widgets fresh
            }
        }

        fun stop(ctx: Context) {
            try {
                ctx.applicationContext.stopService(Intent(ctx.applicationContext, LiveService::class.java))
            } catch (e: Exception) {
                // ignore
            }
        }

        private fun ensureChannel(ctx: Context) {
            if (Build.VERSION.SDK_INT >= 26) {
                val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (nm.getNotificationChannel(CH) == null) {
                    val ch = NotificationChannel(CH, ctx.getString(R.string.live_channel_name), NotificationManager.IMPORTANCE_LOW)
                    ch.description = ctx.getString(R.string.live_channel_desc)
                    ch.setShowBadge(false)
                    ch.setSound(null, null)
                    nm.createNotificationChannel(ch)
                }
            }
        }

        fun buildNotification(ctx: Context): Notification {
            val app = ctx.applicationContext
            ensureChannel(app)
            val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            val launch = app.packageManager.getLaunchIntentForPackage(app.packageName)
            val open = if (launch != null) PendingIntent.getActivity(app, 0, launch, flags) else null
            val stopIntent = Intent(app, LiveService::class.java).setAction(ACTION_STOP)
            val stop = PendingIntent.getService(app, 2, stopIntent, flags)
            val b = NotificationCompat.Builder(app, CH)
                .setSmallIcon(R.drawable.ic_stat_leaf)
                .setContentTitle(app.getString(R.string.live_title))
                .setContentText(WidgetRenderer.summary(app))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .addAction(0, app.getString(R.string.live_stop), stop)
            if (open != null) b.setContentIntent(open)
            return b.build()
        }

        fun notifyIfRunning(ctx: Context) {
            if (!running) return
            try {
                val app = ctx.applicationContext
                val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(NID, buildNotification(app))
            } catch (e: Exception) {
                // ignore
            }
        }
    }
}
