package com.agrisense.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * Turns new system events (watering, cover moves, refusals, device offline, sensor fault)
 * into regular phone notifications. Runs on a background thread right after each refresh.
 */
object EventNotifier {
    private val lock = Any()
    const val CH_EVENTS = "events"
    const val CH_ALERTS = "alerts"
    private const val MAX_SEEN = 100
    private const val MAX_AGE_MS = 6L * 3_600_000L
    private const val MAX_INDIVIDUAL = 5
    private const val SUMMARY_ID = 4301

    private val SRC = mapOf("schedule" to "Scheduled", "manual" to "Manual", "auto_heat" to "Auto, heat")
    private val WHY = mapOf(
        "wet" to "Soil was moist enough",
        "sensor_fault" to "Soil sensor fault",
        "busy" to "Pump was busy",
        "cooldown" to "Cooling down"
    )

    private class Ev(val title: String, val text: String, val problem: Boolean)

    /** Call from a background thread. Never throws. */
    fun run(ctx: Context) {
        val app = ctx.applicationContext
        if (!Notify.enabled(app)) return
        synchronized(lock) {
            try { checkDevice(app) } catch (e: Exception) { /* ignore */ }
            try { checkEvents(app) } catch (e: Exception) { /* ignore */ }
        }
    }

    // ---- device state (offline / back online / soil sensor fault) ----

    private fun checkDevice(app: Context) {
        val s = Snapshots.load(app) ?: return
        if (s.error != null || !s.hasTelemetry) return   // no connection to the server says nothing about the device
        val p = Store.plain(app)
        val state = if (s.onlineAt(System.currentTimeMillis())) "online" else "offline"
        val prev = p.getString("ev_dev_state", null)
        val prevFault = p.getBoolean("ev_soil_fault", false)
        p.edit().putString("ev_dev_state", state).putBoolean("ev_soil_fault", s.soilFault).apply()

        if (prev != null && prev != state) {
            if (state == "offline") {
                post(app, "dev_state", Ev("Device offline", "AgriSense has stopped hearing from your garden device.", true))
            } else {
                post(app, "dev_state", Ev("Device back online", "Your garden device is reporting again.", false))
            }
        }
        if (s.soilFault && !prevFault) {
            post(app, "soil_fault", Ev("Soil sensor fault", "The soil moisture sensor is not giving a valid reading.", true))
        }
    }

    // ---- activity log ----

    private fun keyOf(e: JSONObject): String {
        val id = if (e.has("id") && !e.isNull("id")) e.optString("id") else ""
        return if (id.isNotBlank()) id else "${e.optString("type")}|${e.optString("occurred_at")}"
    }

    private fun checkEvents(app: Context) {
        val body = Net.getAuthed(app, "/api/events?group=all&limit=20") ?: return
        val arr = JSONObject(body).optJSONArray("events") ?: return
        val p = Store.plain(app)

        val seenRaw = p.getString("ev_seen", null)
        val seen = LinkedHashSet<String>()
        if (seenRaw != null) {
            try {
                val a = JSONArray(seenRaw)
                for (i in 0 until a.length()) seen.add(a.getString(i))
            } catch (e: Exception) { /* start over */ }
        }

        val items = ArrayList<JSONObject>()
        for (i in 0 until arr.length()) arr.optJSONObject(i)?.let { items.add(it) }
        val currentKeys = items.map { keyOf(it) }

        val merged = ArrayList<String>(currentKeys)
        for (k in seen) if (k !in currentKeys) merged.add(k)
        val out = JSONArray()
        merged.take(MAX_SEEN).forEach { out.put(it) }
        p.edit().putString("ev_seen", out.toString()).apply()

        // First run after turning notifications on: remember what exists, don't spam old history.
        if (seenRaw == null) return

        val now = System.currentTimeMillis()
        val fresh = items
            .filter { keyOf(it) !in seen }
            .filter {
                val ts = Snapshots.parseIso(it.optString("occurred_at"))
                ts == 0L || now - ts < MAX_AGE_MS
            }
            .sortedBy { Snapshots.parseIso(it.optString("occurred_at")) }
        if (fresh.isEmpty()) return

        val onlyProblems = Notify.onlyProblems(app)
        val evs = fresh.map { it to describe(it) }
            .filter { (_, ev) -> !onlyProblems || ev.problem }
        if (evs.isEmpty()) return

        if (evs.size > MAX_INDIVIDUAL) {
            val anyProblem = evs.any { it.second.problem }
            post(app, "summary", Ev("${evs.size} new events", evs.takeLast(3).joinToString(" · ") { it.second.title }, anyProblem), SUMMARY_ID)
        } else {
            for ((e, ev) in evs) post(app, keyOf(e), ev)
        }
    }

    private fun num(d: JSONObject, k: String): Double? {
        if (!d.has(k) || d.isNull(k)) return null
        val v = d.opt(k)
        return when (v) {
            is Number -> v.toDouble()
            is String -> v.toDoubleOrNull()
            else -> null
        }
    }

    private fun fmt(x: Double): String = if (x == Math.floor(x)) x.toLong().toString() else x.toString()

    private fun join(vararg parts: String?): String = parts.filter { !it.isNullOrBlank() }.joinToString(" · ")

    private fun describe(e: JSONObject): Ev {
        val d = e.optJSONObject("detail") ?: JSONObject()
        val result = if (d.has("result") && !d.isNull("result")) d.optString("result") else null
        val bad = result != null && result != "ok"
        val why = WHY[result ?: ""] ?: result
        val src = e.optString("source").let { SRC[it] ?: it.ifBlank { null } }
        val sp = num(d, "soil_pct")
        val soil = if (sp != null && sp >= 0) "soil ${fmt(sp)}%" else null
        val type = e.optString("type")
        return when (type) {
            "water_auto", "water_manual" -> {
                if (bad) Ev("Watering refused", join(src, why), true)
                else {
                    val secs = num(d, "seconds")
                    Ev("Plants watered", join(src, if (secs != null && secs != 0.0) "${fmt(secs)} s" else null, soil), false)
                }
            }
            "water_skipped" -> {
                val r = d.optString("reason")
                Ev("Watering skipped", join(WHY[r] ?: r, soil), r == "sensor_fault")
            }
            "shade_close", "shade_open" -> {
                val closing = type == "shade_close"
                if (bad) Ev("Cover move refused", join(src, why), true)
                else {
                    val tc = num(d, "temp_c")
                    Ev(if (closing) "Cover closed" else "Cover opened",
                        join(src, if (tc != null && tc != 0.0) "${fmt(tc)}°C" else null), false)
                }
            }
            else -> Ev(type.replace('_', ' ').replaceFirstChar { it.uppercase() }, join(src), bad)
        }
    }

    // ---- posting ----

    private fun ensureChannels(app: Context) {
        if (android.os.Build.VERSION.SDK_INT < 26) return
        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CH_EVENTS) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CH_EVENTS, app.getString(R.string.events_channel_name), NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = app.getString(R.string.events_channel_desc) }
            )
        }
        if (nm.getNotificationChannel(CH_ALERTS) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CH_ALERTS, app.getString(R.string.alerts_channel_name), NotificationManager.IMPORTANCE_HIGH)
                    .apply { description = app.getString(R.string.alerts_channel_desc) }
            )
        }
    }

    private fun post(app: Context, key: String, ev: Ev, idOverride: Int? = null) {
        try {
            if (!NotificationManagerCompat.from(app).areNotificationsEnabled()) return
            ensureChannels(app)
            val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            val launch = app.packageManager.getLaunchIntentForPackage(app.packageName)
            val open = if (launch != null) PendingIntent.getActivity(app, 1, launch, flags) else null
            val b = NotificationCompat.Builder(app, if (ev.problem) CH_ALERTS else CH_EVENTS)
                .setSmallIcon(R.drawable.ic_stat_leaf)
                .setContentTitle(ev.title)
                .setContentText(ev.text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(ev.text))
                .setAutoCancel(true)
                .setWhen(System.currentTimeMillis())
                .setShowWhen(true)
                .setCategory(if (ev.problem) NotificationCompat.CATEGORY_ERROR else NotificationCompat.CATEGORY_STATUS)
                .setPriority(if (ev.problem) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
            if (open != null) b.setContentIntent(open)
            val id = idOverride ?: (20_000 + (key.hashCode() and 0x3fffffff) % 1_000_000)
            NotificationManagerCompat.from(app).notify(id, b.build())
        } catch (e: SecurityException) {
            // notification permission not granted
        } catch (e: Exception) {
            // ignore
        }
    }
}
