package com.agrisense.app

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView

class WidgetConfigActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density + 0.5f).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        widgetId = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        val cfg = WidgetPrefs.load(this, widgetId)

        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.setPadding(dp(24), dp(20), dp(24), dp(24))

        fun heading(text: String) {
            val t = TextView(this)
            t.text = text
            t.textSize = 13f
            t.setTypeface(null, Typeface.BOLD)
            t.setTextColor(0xFF7D8869.toInt())
            t.setPadding(0, dp(18), 0, dp(6))
            col.addView(t)
        }

        val title = TextView(this)
        title.text = getString(R.string.widget_config_title)
        title.textSize = 22f
        title.setTypeface(null, Typeface.BOLD)
        title.setTextColor(0xFF34471D.toInt())
        col.addView(title)

        heading("SHOW")
        val cbT = CheckBox(this)
        cbT.text = "Temperature"
        cbT.isChecked = cfg.temp
        val cbH = CheckBox(this)
        cbH.text = "Humidity"
        cbH.isChecked = cfg.hum
        val cbS = CheckBox(this)
        cbS.text = "Soil moisture"
        cbS.isChecked = cfg.soil
        val cbO = CheckBox(this)
        cbO.text = "Online / offline status"
        cbO.isChecked = cfg.status
        col.addView(cbT)
        col.addView(cbH)
        col.addView(cbS)
        col.addView(cbO)

        heading("STYLE")
        val group = RadioGroup(this)
        group.orientation = RadioGroup.VERTICAL
        val themes = arrayOf(
            "light" to "Matcha light",
            "dark" to "Dark",
            "auto" to "Follow system",
            "transparent" to "Transparent (no background)"
        )
        val ids = IntArray(themes.size)
        for (i in themes.indices) {
            val rb = RadioButton(this)
            rb.id = View.generateViewId()
            rb.text = themes[i].second
            ids[i] = rb.id
            group.addView(rb, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        val cur = themes.indexOfFirst { it.first == cfg.theme }.let { if (it < 0) 0 else it }
        group.check(ids[cur])
        col.addView(group)

        heading("BACKGROUND OPACITY")
        val opLabel = TextView(this)
        opLabel.text = "${cfg.opacity}%"
        val seek = SeekBar(this)
        seek.max = 100
        seek.progress = cfg.opacity
        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(sb: SeekBar?, progress: Int, fromUser: Boolean) {
                opLabel.text = "$progress%"
            }

            override fun onStartTrackingTouch(sb: SeekBar?) {}
            override fun onStopTrackingTouch(sb: SeekBar?) {}
        })
        col.addView(opLabel)
        col.addView(seek)

        val hint = TextView(this)
        hint.text = "Resize the widget on your home screen to change its layout. Everything scales to fit."
        hint.textSize = 12f
        hint.setTextColor(0xFF7D8869.toInt())
        hint.setPadding(0, dp(18), 0, 0)
        col.addView(hint)

        val save = Button(this)
        save.text = "Save"
        save.setOnClickListener {
            var t = cbT.isChecked
            val h = cbH.isChecked
            val s = cbS.isChecked
            val o = cbO.isChecked
            if (!t && !h && !s && !o) t = true
            val idx = ids.indexOf(group.checkedRadioButtonId).let { if (it < 0) 0 else it }
            WidgetPrefs.save(this, widgetId, WidgetConfig(t, h, s, o, themes[idx].first, seek.progress))
            AgriWidgetProvider.renderWidget(this, widgetId)
            RefreshWorker.enqueueOnce(this)
            setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
            finish()
        }
        val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        lp.topMargin = dp(16)
        col.addView(save, lp)

        val sv = ScrollView(this)
        sv.addView(col)
        setContentView(sv)
    }
}
