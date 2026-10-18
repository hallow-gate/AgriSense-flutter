package com.agrisense.app

import android.content.Context
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

data class Snapshot(
    val tempC: Double?,
    val humidity: Double?,
    val soilPct: Double?,
    val soilFault: Boolean,
    val serverOnline: Boolean,
    val hasTelemetry: Boolean,
    val updatedAtMs: Long,
    val fetchedAtMs: Long,
    val error: String?          // "signed_out" | "network" | null
) {
    /** Online if the server said so at fetch time and the last device report is still fresh now. */
    fun onlineAt(now: Long): Boolean {
        if (!hasTelemetry || !serverOnline || error == "network") return false
        return updatedAtMs <= 0L || now - updatedAtMs < 120_000L
    }

    fun toJson(): String {
        val o = JSONObject()
        if (tempC != null) o.put("tempC", tempC)
        if (humidity != null) o.put("humidity", humidity)
        if (soilPct != null) o.put("soilPct", soilPct)
        o.put("soilFault", soilFault)
        o.put("serverOnline", serverOnline)
        o.put("hasTelemetry", hasTelemetry)
        o.put("updatedAtMs", updatedAtMs)
        o.put("fetchedAtMs", fetchedAtMs)
        if (error != null) o.put("error", error)
        return o.toString()
    }
}

object Snapshots {
    private const val KEY = "snapshot"

    fun empty(): Snapshot = Snapshot(null, null, null, false, false, false, 0L, 0L, null)

    private fun dbl(o: JSONObject, k: String): Double? {
        if (!o.has(k) || o.isNull(k)) return null
        val d = o.optDouble(k, Double.NaN)
        return if (d.isNaN()) null else d
    }

    fun parseIso(s: String?): Long {
        if (s.isNullOrBlank()) return 0L
        return try {
            var t = s.trim()
            var offsetMs = 0L
            val m = Regex("(Z|[+-]\\d{2}:?\\d{2})$").find(t)
            if (m != null) {
                val z = m.value
                t = t.substring(0, m.range.first)
                if (z != "Z") {
                    val sign = if (z[0] == '-') -1L else 1L
                    val digits = z.substring(1).replace(":", "")
                    val hh = digits.substring(0, 2).toLong()
                    val mm = digits.substring(2, 4).toLong()
                    offsetMs = sign * (hh * 3_600_000L + mm * 60_000L)
                }
            }
            var frac = 0L
            val dot = t.indexOf('.')
            if (dot >= 0) {
                val digits = t.substring(dot + 1).filter { it.isDigit() }.take(3).padEnd(3, '0')
                frac = digits.toLong()
                t = t.substring(0, dot)
            }
            t = t.replace(' ', 'T')
            val f = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
            f.timeZone = TimeZone.getTimeZone("UTC")
            val base = f.parse(t)?.time ?: return 0L
            base + frac - offsetMs
        } catch (e: Exception) {
            0L
        }
    }

    /** Parses the body of GET /api/status. Throws on invalid JSON. */
    fun parse(body: String, now: Long): Snapshot {
        val root = JSONObject(body)
        val tel = root.optJSONObject("telemetry")
        val serverOnline = root.optBoolean("online", false)
        if (tel == null) {
            return Snapshot(null, null, null, false, serverOnline, false, 0L, now, null)
        }
        val sf = tel.opt("soil_fault")
        val fault = sf == true || (sf is Number && sf.toInt() != 0)
        return Snapshot(
            tempC = dbl(tel, "temp_c"),
            humidity = dbl(tel, "humidity"),
            soilPct = if (fault) null else dbl(tel, "soil_pct"),
            soilFault = fault,
            serverOnline = serverOnline,
            hasTelemetry = true,
            updatedAtMs = parseIso(if (tel.isNull("updated_at")) null else tel.optString("updated_at")),
            fetchedAtMs = now,
            error = null
        )
    }

    fun save(ctx: Context, s: Snapshot) {
        Store.plain(ctx).edit().putString(KEY, s.toJson()).apply()
    }

    fun load(ctx: Context): Snapshot? {
        val raw = Store.plain(ctx).getString(KEY, null) ?: return null
        return try {
            val o = JSONObject(raw)
            Snapshot(
                tempC = dbl(o, "tempC"),
                humidity = dbl(o, "humidity"),
                soilPct = dbl(o, "soilPct"),
                soilFault = o.optBoolean("soilFault", false),
                serverOnline = o.optBoolean("serverOnline", false),
                hasTelemetry = o.optBoolean("hasTelemetry", false),
                updatedAtMs = o.optLong("updatedAtMs", 0L),
                fetchedAtMs = o.optLong("fetchedAtMs", 0L),
                error = if (o.has("error") && !o.isNull("error")) o.optString("error") else null
            )
        } catch (e: Exception) {
            null
        }
    }

    fun clear(ctx: Context) {
        Store.plain(ctx).edit().remove(KEY).apply()
    }
}
