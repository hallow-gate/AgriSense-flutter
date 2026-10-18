package com.agrisense.app

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var notifResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("native", e.message, null)
            }
        }
    }

    /** Accepts either a bare string argument or a map holding it under one of [names]. */
    private fun argStr(call: MethodCall, vararg names: String): String? {
        val a = call.arguments
        if (a is String) return a
        if (a is Map<*, *>) {
            for (n in names) {
                val v = a[n]
                if (v is String) return v
            }
        }
        return null
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "kvGet" -> {
                val k = argStr(call, "key")
                if (k == null) result.error("args", "key missing", null) else result.success(Store.kvGet(this, k))
            }
            "kvSet" -> {
                val k = argStr(call, "key")
                val v = (call.arguments as? Map<*, *>)?.get("value") as? String
                if (k == null || v == null) {
                    result.error("args", "key/value missing", null)
                } else {
                    Store.kvSet(this, k, v)
                    result.success(null)
                }
            }
            "kvDelete" -> {
                val k = argStr(call, "key")
                if (k == null) {
                    result.error("args", "key missing", null)
                } else {
                    Store.kvDelete(this, k)
                    result.success(null)
                }
            }
            "setBaseUrl" -> {
                val u = argStr(call, "url", "value", "base")
                if (u == null) {
                    result.error("args", "url missing", null)
                } else {
                    Store.kvSet(this, Store.KEY_BASE, u.trim().trimEnd('/'))
                    result.success(null)
                }
            }
            "pushStatus" -> {
                val body = argStr(call, "json", "body", "status", "value")
                if (body == null) {
                    result.error("args", "json missing", null)
                } else {
                    try {
                        val snap = Snapshots.parse(body, System.currentTimeMillis())
                        Snapshots.save(this, snap)
                        Updater.onChanged(this)
                    } catch (e: Exception) {
                        // ignore a malformed body; the widget keeps its last data
                    }
                    result.success(null)
                }
            }
            "setLive" -> {
                val m = call.arguments as? Map<*, *>
                val enabled = (m?.get("enabled") as? Boolean) ?: false
                val sec = (m?.get("intervalSec") as? Number)?.toInt() ?: Live.intervalSec(this)
                Live.set(this, enabled, sec)
                if (enabled || Notify.instantActive(this)) LiveService.start(this) else LiveService.stop(this)
                result.success(null)
            }
            "getLive" -> {
                result.success(mapOf("enabled" to Live.enabled(this), "intervalSec" to Live.intervalSec(this)))
            }
            "setNotify" -> {
                val m = call.arguments as? Map<*, *>
                val enabled = (m?.get("enabled") as? Boolean) ?: false
                val only = (m?.get("onlyProblems") as? Boolean) ?: false
                val instant = (m?.get("instant") as? Boolean) ?: false
                Notify.set(this, enabled, only, instant)
                if (enabled && instant) LiveService.start(this)
                else if (!Live.enabled(this)) LiveService.stop(this)
                if (enabled) {
                    RefreshWorker.schedulePeriodic(this)
                    RefreshWorker.enqueueOnce(this)
                } else if (AgriWidgetProvider.count(this) == 0) {
                    RefreshWorker.cancelPeriodic(this)
                }
                result.success(null)
            }
            "getNotify" -> {
                // self-heal: restart the watcher if instant alerts are on but the service was stopped (e.g. after sign-out)
                if (Notify.instantActive(this) && !LiveService.running) LiveService.start(this)
                result.success(mapOf("enabled" to Notify.enabled(this), "onlyProblems" to Notify.onlyProblems(this), "instant" to Notify.instant(this)))
            }
            "widgetCount" -> result.success(AgriWidgetProvider.count(this))
            "requestPinWidget" -> {
                var ok = false
                if (Build.VERSION.SDK_INT >= 26) {
                    val mgr = AppWidgetManager.getInstance(this)
                    if (mgr.isRequestPinAppWidgetSupported) {
                        ok = mgr.requestPinAppWidget(ComponentName(this, AgriWidgetProvider::class.java), null, null)
                    }
                }
                result.success(ok)
            }
            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT < 33 ||
                    ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                ) {
                    result.success(true)
                } else {
                    notifResult?.success(false)
                    notifResult = result
                    ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
                }
            }
            "openBatterySettings" -> {
                try {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                } catch (e: Exception) {
                    startActivity(Intent(Settings.ACTION_SETTINGS))
                }
                result.success(null)
            }
            "clearWidgetData" -> {
                Snapshots.clear(this)
                Live.set(this, false, Live.intervalSec(this))
                LiveService.stop(this)
                Updater.onChanged(this)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIF) {
            notifResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            notifResult = null
        }
    }

    companion object {
        const val CHANNEL = "com.agrisense.app/native"
        private const val REQ_NOTIF = 7101
    }
}
