package com.agrisense.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.SystemClock
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

object WidgetRenderer {
    private const val ROW = 0
    private const val GRID = 1
    private const val STACK = 2

    private class Pal(
        val bgRes: Int,
        val ink: Int,
        val mute: Int,
        val temp: Int,
        val hum: Int,
        val soil: Int,
        val ok: Int,
        val bad: Int,
        val grey: Int
    )

    private fun palette(ctx: Context, theme: String): Pal {
        val night = (ctx.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val dark = theme == "dark" || (theme == "auto" && night)
        return when {
            theme == "transparent" -> Pal(
                R.drawable.bg_dark, 0xFFFFFFFF.toInt(), 0xCCFFFFFF.toInt(),
                0xFFFFB27A.toInt(), 0xFF9FD3D9.toInt(), 0xFFB7D88C.toInt(),
                0xFF8FD16A.toInt(), 0xFFFF8A73.toInt(), 0xFFBDBDBD.toInt()
            )
            dark -> Pal(
                R.drawable.bg_dark, 0xFFEAF0DC.toInt(), 0xFFA7B190.toInt(),
                0xFFE3A66E.toInt(), 0xFF8EC0C6.toInt(), 0xFF9DBA72.toInt(),
                0xFF8FBF5F.toInt(), 0xFFE2826C.toInt(), 0xFF8A927B.toInt()
            )
            else -> Pal(
                R.drawable.bg_light, 0xFF2A3320.toInt(), 0xFF7D8869.toInt(),
                0xFFCF8A52.toInt(), 0xFF6E9EA3.toInt(), 0xFF5F7F3A.toInt(),
                0xFF6F8F45.toInt(), 0xFFB45742.toInt(), 0xFF9AA088.toInt()
            )
        }
    }

    private fun withAlpha(c: Int, a: Int): Int = (c and 0x00FFFFFF) or (a.coerceIn(0, 255) shl 24)
    private fun clampF(v: Float, lo: Float, hi: Float): Float = max(lo, min(hi, v))

    /** Size of this widget instance in dp, from the launcher's options (updated on every resize). */
    fun sizeOf(ctx: Context, mgr: AppWidgetManager, id: Int): IntArray {
        val o = mgr.getAppWidgetOptions(id)
        val portrait = ctx.resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
        var w = if (portrait) o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) else o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        var h = if (portrait) o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0) else o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        if (w <= 0) w = 250
        if (h <= 0) h = 110
        return intArrayOf(w, h)
    }

    fun buildFor(ctx: Context, mgr: AppWidgetManager, id: Int): RemoteViews {
        val s = sizeOf(ctx, mgr, id)
        return build(ctx, id, s[0], s[1])
    }

    /** Short text for the live notification. */
    fun summary(ctx: Context): String {
        val app = ctx.applicationContext
        val snap = Snapshots.load(app)
        if (Store.session(app) == null || snap?.error == "signed_out") return "Sign in to AgriSense"
        if (snap == null || !snap.hasTelemetry) return "Waiting for data…"
        val now = System.currentTimeMillis()
        val t = snap.tempC?.let { String.format(Locale.US, "%.1f°", it) } ?: "–"
        val h = snap.humidity?.let { "${it.roundToInt()}%" } ?: "–"
        val s = if (snap.soilFault) "fault" else snap.soilPct?.let { "${it.roundToInt()}%" } ?: "–"
        val st = if (snap.error == "network") "No connection" else if (snap.onlineAt(now)) "Online" else "Offline"
        return "$t · $h · soil $s · $st"
    }

    fun build(ctx: Context, id: Int, w: Int, h: Int): RemoteViews {
        val app = ctx.applicationContext
        val density = app.resources.displayMetrics.density
        fun px(dp: Float): Int = (dp * density).roundToInt()

        val cfg = WidgetPrefs.load(app, id)
        val snap = Snapshots.load(app)
        val now = System.currentTimeMillis()
        val signedOut = Store.session(app) == null || snap?.error == "signed_out"
        val noConn = !signedOut && snap?.error == "network"
        val online = !signedOut && snap != null && snap.onlineAt(now)
        val pal = palette(app, cfg.theme)

        val layout = when {
            signedOut -> ROW
            w >= 1.8f * h && w >= 130 -> ROW
            w >= 100 && h >= 100 -> GRID
            else -> STACK
        }
        val layoutRes = when (layout) {
            ROW -> R.layout.widget_row
            GRID -> R.layout.widget_grid
            else -> R.layout.widget_stack
        }
        val v = RemoteViews(app.packageName, layoutRes)

        // ---- what to show ----
        var showT = !signedOut && cfg.temp
        var showH = !signedOut && cfg.hum
        var showS = !signedOut && cfg.soil
        val showStatus = signedOut || cfg.status
        if (!signedOut && !showT && !showH && !showS && !showStatus) showT = true

        // ---- text ----
        val tTxt = snap?.tempC?.let { String.format(Locale.US, "%.1f°", it) } ?: "–"
        val hTxt = snap?.humidity?.let { "${it.roundToInt()}%" } ?: "–"
        val sTxt = if (snap?.soilFault == true) "Fault" else snap?.soilPct?.let { "${it.roundToInt()}%" } ?: "–"
        val statusTxt = when {
            signedOut -> "Sign in to AgriSense"
            noConn -> "No connection"
            snap == null || !snap.hasTelemetry -> "No data"
            online -> "Online"
            else -> "Offline"
        }
        val dotColor = when {
            signedOut || noConn || snap == null || !snap.hasTelemetry -> pal.grey
            online -> pal.ok
            else -> pal.bad
        }
        val dim = !online
        val ink = if (dim) withAlpha(pal.ink, 0x88) else pal.ink
        val mute = if (dim) withAlpha(pal.mute, 0x88) else pal.mute

        // ---- background ----
        if (cfg.theme == "transparent") {
            v.setViewVisibility(R.id.bg, View.GONE)
        } else {
            v.setViewVisibility(R.id.bg, View.VISIBLE)
            v.setImageViewResource(R.id.bg, pal.bgRes)
            v.setInt(R.id.bg, "setImageAlpha", cfg.opacity.coerceIn(0, 100) * 255 / 100)
        }

        // ---- visibility ----
        v.setViewVisibility(R.id.cell_temp, if (showT) View.VISIBLE else View.GONE)
        v.setViewVisibility(R.id.cell_hum, if (showH) View.VISIBLE else View.GONE)
        v.setViewVisibility(R.id.cell_soil, if (showS) View.VISIBLE else View.GONE)
        v.setViewVisibility(R.id.cell_status, if (showStatus) View.VISIBLE else View.GONE)
        if (layout == GRID) v.setViewVisibility(R.id.grid_row1, if (showT || showH) View.VISIBLE else View.GONE)

        // ---- content ----
        v.setTextViewText(R.id.val_temp, tTxt)
        v.setTextViewText(R.id.val_hum, hTxt)
        v.setTextViewText(R.id.val_soil, sTxt)
        v.setTextViewText(R.id.val_status, statusTxt)
        v.setTextColor(R.id.val_temp, ink)
        v.setTextColor(R.id.val_hum, ink)
        v.setTextColor(R.id.val_soil, ink)
        v.setTextColor(R.id.val_status, ink)
        v.setInt(R.id.dot, "setColorFilter", dotColor)
        val icT = if (dim) withAlpha(pal.temp, 0x88) else pal.temp
        val icH = if (dim) withAlpha(pal.hum, 0x88) else pal.hum
        val icS = if (dim) withAlpha(pal.soil, 0x88) else pal.soil
        v.setInt(R.id.ic_temp, "setColorFilter", icT)
        v.setInt(R.id.ic_hum, "setColorFilter", icH)
        v.setInt(R.id.ic_soil, "setColorFilter", icS)

        fun sp(viewId: Int, size: Float) = v.setTextViewTextSize(viewId, TypedValue.COMPLEX_UNIT_SP, size)
        fun icon(viewId: Int, show: Boolean, dp: Float) {
            v.setViewVisibility(viewId, if (show) View.VISIBLE else View.GONE)
            if (show && Build.VERSION.SDK_INT >= 31) {
                v.setViewLayoutWidth(viewId, dp, TypedValue.COMPLEX_UNIT_DIP)
                v.setViewLayoutHeight(viewId, dp, TypedValue.COMPLEX_UNIT_DIP)
            }
        }
        fun pad(viewId: Int, dp: Float) {
            val p = px(dp)
            v.setViewPadding(viewId, p, p, p, p)
        }
        fun labels(show: Boolean, size: Float) {
            for (lid in intArrayOf(R.id.lbl_temp, R.id.lbl_hum, R.id.lbl_soil)) {
                v.setViewVisibility(lid, if (show) View.VISIBLE else View.GONE)
                v.setTextColor(lid, mute)
                if (show) sp(lid, size)
            }
        }
        val ageMs = if (snap != null && snap.updatedAtMs > 0L) max(0L, now - snap.updatedAtMs) else -1L
        fun chrono(show: Boolean, size: Float) {
            val ok = show && ageMs >= 0L
            v.setViewVisibility(R.id.age, if (ok) View.VISIBLE else View.GONE)
            if (ok) {
                v.setChronometer(R.id.age, SystemClock.elapsedRealtime() - ageMs, "%s ago", true)
                v.setTextColor(R.id.age, mute)
                sp(R.id.age, size)
            }
        }
        fun refreshBtn(show: Boolean) {
            v.setViewVisibility(R.id.refresh, if (show) View.VISIBLE else View.GONE)
            if (show) v.setInt(R.id.refresh, "setColorFilter", mute)
        }
        fun statusSize(base: Float, availW: Float, lo: Float, hi: Float): Float {
            val len = max(4, statusTxt.length).toFloat()
            return clampF(min(base, availW / (len * 0.56f)), lo, hi)
        }

        when (layout) {
            ROW -> {
                val n = max(1, listOf(showT, showH, showS, showStatus).count { it })
                val padDp = clampF(h * 0.08f, 3f, 10f)
                val cellW = (w - 2 * padDp) / n
                val cellH = h - 2 * padDp
                val labelsOn = cellH >= 60f && !signedOut
                val iconsOn = cellH >= 46f && !signedOut
                val valSp = clampF(min(cellH * (if (labelsOn) 0.36f else 0.5f), cellW / 3.0f), 10f, 38f)
                val lblSp = clampF(valSp * 0.4f, 8f, 12f)
                pad(R.id.content, padDp)
                sp(R.id.val_temp, valSp)
                sp(R.id.val_hum, valSp)
                sp(R.id.val_soil, valSp)
                labels(labelsOn, lblSp)
                val iconDp = clampF(valSp * 0.7f, 12f, 26f)
                icon(R.id.ic_temp, iconsOn, iconDp)
                icon(R.id.ic_hum, iconsOn, iconDp)
                icon(R.id.ic_soil, iconsOn, iconDp)
                if (signedOut) {
                    sp(R.id.val_status, statusSize(cellH * 0.34f, cellW, 8f, 20f))
                    v.setViewVisibility(R.id.dot, View.GONE)
                } else {
                    v.setViewVisibility(R.id.dot, View.VISIBLE)
                    sp(R.id.val_status, statusSize(min(valSp * 0.62f, cellH * 0.3f), cellW, 8f, 18f))
                }
                chrono(cellH >= 70f && showStatus && !signedOut, lblSp)
                refreshBtn(!signedOut && h >= 64 && w >= 160)
            }
            GRID -> {
                val padDp = clampF(min(w, h) * 0.07f, 5f, 12f)
                val hdr = clampF(h * 0.17f, 18f, 30f)
                val rows = (if (showT || showH) 1 else 0) + (if (showS) 1 else 0)
                val bodyH = h - 2 * padDp - (if (showStatus) hdr else 0f)
                val rowH = bodyH / max(1, rows)
                val cols = max(1, (if (showT) 1 else 0) + (if (showH) 1 else 0))
                val cellW = (w - 2 * padDp) / cols
                val labelsOn = rowH >= 44f
                val iconsOn = rowH >= 38f
                val valSp = clampF(min(rowH * (if (labelsOn) 0.38f else 0.55f), cellW / 3.0f), 10f, 40f)
                val soilSp = clampF(min(rowH * (if (labelsOn) 0.3f else 0.5f), (w - 2 * padDp) / 3.0f), 10f, 40f)
                val lblSp = clampF(valSp * 0.4f, 8f, 12f)
                val hdrSp = clampF(hdr * 0.45f, 9f, 14f)
                pad(R.id.content, padDp)
                sp(R.id.val_temp, valSp)
                sp(R.id.val_hum, valSp)
                sp(R.id.val_soil, soilSp)
                labels(labelsOn, lblSp)
                icon(R.id.ic_temp, iconsOn, clampF(valSp * 0.7f, 12f, 26f))
                icon(R.id.ic_hum, iconsOn, clampF(valSp * 0.7f, 12f, 26f))
                icon(R.id.ic_soil, iconsOn, clampF(soilSp * 0.7f, 12f, 26f))
                sp(R.id.val_status, hdrSp)
                chrono(w >= 170 && showStatus, hdrSp * 0.85f)
                refreshBtn(showStatus && w >= 120)
                val showBar = showS && rowH >= 40f
                v.setViewVisibility(R.id.bar_soil, if (showBar) View.VISIBLE else View.GONE)
                if (showBar) v.setProgressBar(R.id.bar_soil, 100, (snap?.soilPct?.roundToInt() ?: 0).coerceIn(0, 100), false)
            }
            else -> {
                val lines = max(1, listOf(showT, showH, showS, showStatus).count { it })
                val padDp = clampF(min(w, h) * 0.08f, 2f, 8f)
                val lineH = (h - 2 * padDp) / lines
                val iconDp = if (lineH >= 16f && w >= 56) clampF(lineH * 0.6f, 10f, 22f) else 0f
                val valSp = clampF(min(lineH * 0.58f, (w - 2 * padDp - iconDp - 4f) / 4.2f), 8f, 30f)
                pad(R.id.content, padDp)
                sp(R.id.val_temp, valSp)
                sp(R.id.val_hum, valSp)
                sp(R.id.val_soil, valSp)
                val iconsOn = iconDp > 0f
                icon(R.id.ic_temp, iconsOn, iconDp)
                icon(R.id.ic_hum, iconsOn, iconDp)
                icon(R.id.ic_soil, iconsOn, iconDp)
                sp(R.id.val_status, statusSize(min(valSp * 0.85f, lineH * 0.6f), w - 2 * padDp - 14f, 7f, 20f))
            }
        }

        // ---- taps ----
        val launch = app.packageManager.getLaunchIntentForPackage(app.packageName)
        if (launch != null) {
            val open = PendingIntent.getActivity(app, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            v.setOnClickPendingIntent(R.id.root, open)
        }
        if (layout != STACK) {
            val ri = Intent(app, AgriWidgetProvider::class.java).setAction(AgriWidgetProvider.ACTION_REFRESH)
            val rp = PendingIntent.getBroadcast(app, 1, ri, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            v.setOnClickPendingIntent(R.id.refresh, rp)
        }
        return v
    }
}
