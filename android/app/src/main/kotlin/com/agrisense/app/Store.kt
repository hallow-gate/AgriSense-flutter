package com.agrisense.app

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONObject
import java.io.File

/** Secure key/value store shared by the Flutter app and the native widget code. */
object Store {
    const val SECURE_FILE = "agrisense_secure"
    const val PLAIN_FILE = "agrisense_widget"
    const val KEY_SESSION = "agrisense.session"
    const val KEY_BASE = "agrisense.base"

    @Volatile
    private var secureCache: SharedPreferences? = null

    fun plain(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences(PLAIN_FILE, Context.MODE_PRIVATE)

    private fun createEncrypted(app: Context): SharedPreferences {
        val key = MasterKey.Builder(app).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        return EncryptedSharedPreferences.create(
            app,
            SECURE_FILE,
            key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    @Synchronized
    fun secure(ctx: Context): SharedPreferences {
        secureCache?.let { return it }
        val app = ctx.applicationContext
        val prefs: SharedPreferences = try {
            createEncrypted(app)
        } catch (e: Exception) {
            try {
                File(app.applicationInfo.dataDir, "shared_prefs/$SECURE_FILE.xml").delete()
                createEncrypted(app)
            } catch (e2: Exception) {
                app.getSharedPreferences(SECURE_FILE + "_fallback", Context.MODE_PRIVATE)
            }
        }
        secureCache = prefs
        return prefs
    }

    fun kvGet(ctx: Context, key: String): String? = secure(ctx).getString(key, null)
    fun kvSet(ctx: Context, key: String, value: String) {
        secure(ctx).edit().putString(key, value).commit()
    }

    fun kvDelete(ctx: Context, key: String) {
        secure(ctx).edit().remove(key).commit()
    }

    fun session(ctx: Context): JSONObject? {
        val raw = kvGet(ctx, KEY_SESSION) ?: return null
        return try {
            JSONObject(raw)
        } catch (e: Exception) {
            null
        }
    }

    fun baseUrl(ctx: Context): String = (kvGet(ctx, KEY_BASE) ?: "").trim().trimEnd('/')
}

/** Live-mode (foreground service) settings. */
object Live {
    fun enabled(ctx: Context): Boolean = Store.plain(ctx).getBoolean("live_enabled", false)
    fun intervalSec(ctx: Context): Int = Store.plain(ctx).getInt("live_interval", 10).coerceIn(5, 300)
    fun set(ctx: Context, enabled: Boolean, sec: Int) {
        Store.plain(ctx).edit()
            .putBoolean("live_enabled", enabled)
            .putInt("live_interval", sec.coerceIn(5, 300))
            .apply()
    }
}

data class WidgetConfig(
    val temp: Boolean = true,
    val hum: Boolean = true,
    val soil: Boolean = true,
    val status: Boolean = true,
    val theme: String = "light",   // light | dark | auto | transparent
    val opacity: Int = 100
)

object WidgetPrefs {
    fun load(ctx: Context, id: Int): WidgetConfig {
        val p = Store.plain(ctx)
        val fields = p.getString("w${id}_fields", null)
        val set = fields?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }?.toSet()
        return WidgetConfig(
            temp = set?.contains("temp") ?: true,
            hum = set?.contains("hum") ?: true,
            soil = set?.contains("soil") ?: true,
            status = set?.contains("status") ?: true,
            theme = p.getString("w${id}_theme", "light") ?: "light",
            opacity = p.getInt("w${id}_opacity", 100).coerceIn(0, 100)
        )
    }

    fun save(ctx: Context, id: Int, c: WidgetConfig) {
        val f = ArrayList<String>()
        if (c.temp) f.add("temp")
        if (c.hum) f.add("hum")
        if (c.soil) f.add("soil")
        if (c.status) f.add("status")
        Store.plain(ctx).edit()
            .putString("w${id}_fields", f.joinToString(","))
            .putString("w${id}_theme", c.theme)
            .putInt("w${id}_opacity", c.opacity.coerceIn(0, 100))
            .apply()
    }

    fun delete(ctx: Context, id: Int) {
        Store.plain(ctx).edit()
            .remove("w${id}_fields").remove("w${id}_theme").remove("w${id}_opacity")
            .apply()
    }
}
