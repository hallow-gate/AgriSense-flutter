package com.agrisense.app

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** Native copy of the app's API client: just enough to read /api/status and keep the session fresh. */
object Net {
    private val lock = Any()
    private const val OK = 0
    private const val DENIED = 1
    private const val NETWORK = 2

    private class Resp(val code: Int, val body: String)

    private fun request(url: String, method: String, token: String?, json: String?): Resp {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = method
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000
            conn.setRequestProperty("Accept", "application/json")
            conn.setRequestProperty("User-Agent", "AgriSense-Android-Widget")
            if (token != null) conn.setRequestProperty("Authorization", "Bearer $token")
            if (json != null) {
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.outputStream.use { it.write(json.toByteArray(Charsets.UTF_8)) }
            }
            val code = conn.responseCode
            val stream = if (code in 200..399) conn.inputStream else conn.errorStream
            val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
            return Resp(code, body)
        } finally {
            conn.disconnect()
        }
    }

    /** Refreshes the stored session. [usedToken] is the access token the caller just used. */
    private fun refresh(ctx: Context, usedToken: String?): Int = synchronized(lock) {
        val cur = Store.session(ctx) ?: return DENIED
        val base = Store.baseUrl(ctx)
        val nowSec = System.currentTimeMillis() / 1000
        // Someone else (the Flutter app) may already have refreshed while we waited for the lock.
        if (usedToken != null && cur.optString("access_token") != usedToken && cur.optLong("expires_at", 0L) - nowSec > 60) {
            return OK
        }
        val rt = cur.optString("refresh_token")
        if (rt.isBlank() || base.isEmpty()) return DENIED
        try {
            val r = request("$base/api/auth/refresh", "POST", null, JSONObject().put("refresh_token", rt).toString())
            if (r.code in 200..299) {
                val j = JSONObject(r.body)
                if (j.optString("access_token").isNotBlank()) {
                    Store.kvSet(ctx, Store.KEY_SESSION, r.body)
                    OK
                } else NETWORK
            } else if (r.code == 401 || r.code == 403) DENIED
            else NETWORK
        } catch (e: Exception) {
            NETWORK
        }
    }

    /** Authenticated GET of any API path. Returns the body on success, null otherwise. Call from a background thread. */
    fun getAuthed(ctx: Context, path: String): String? {
        val app = ctx.applicationContext
        val base = Store.baseUrl(app)
        var session = Store.session(app) ?: return null
        if (base.isEmpty()) return null
        if (session.optLong("expires_at", 0L) - System.currentTimeMillis() / 1000 < 60) {
            if (refresh(app, session.optString("access_token")) != OK) return null
            session = Store.session(app) ?: return null
        }
        return try {
            var token = session.optString("access_token")
            var resp = request("$base$path", "GET", token, null)
            if (resp.code == 401) {
                if (refresh(app, token) != OK) return null
                token = (Store.session(app) ?: return null).optString("access_token")
                resp = request("$base$path", "GET", token, null)
            }
            if (resp.code in 200..299) resp.body else null
        } catch (e: Exception) {
            null
        }
    }

    private fun fail(ctx: Context, err: String): Snapshot {
        val last = Snapshots.load(ctx) ?: Snapshots.empty()
        val s = last.copy(error = err)
        Snapshots.save(ctx, s)
        return s
    }

    /** Fetches /api/status, stores the snapshot and returns it. Never throws. Call from a background thread. */
    fun fetchAndStore(ctx: Context): Snapshot {
        val app = ctx.applicationContext
        val base = Store.baseUrl(app)
        var session = Store.session(app)
        if (session == null || base.isEmpty()) return fail(app, "signed_out")

        if (session.optLong("expires_at", 0L) - System.currentTimeMillis() / 1000 < 60) {
            val r = refresh(app, session.optString("access_token"))
            if (r == DENIED) return fail(app, "signed_out")
            session = Store.session(app) ?: return fail(app, "signed_out")
        }

        return try {
            var token = session.optString("access_token")
            var resp = request("$base/api/status", "GET", token, null)
            if (resp.code == 401) {
                val r = refresh(app, token)
                if (r == DENIED) return fail(app, "signed_out")
                if (r == NETWORK) return fail(app, "network")
                token = (Store.session(app) ?: return fail(app, "signed_out")).optString("access_token")
                resp = request("$base/api/status", "GET", token, null)
            }
            if (resp.code == 401 || resp.code == 403) {
                fail(app, "signed_out")
            } else if (resp.code !in 200..299) {
                fail(app, "network")
            } else {
                val s = Snapshots.parse(resp.body, System.currentTimeMillis())
                Snapshots.save(app, s)
                s
            }
        } catch (e: Exception) {
            fail(app, "network")
        }
    }
}
