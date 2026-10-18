package com.agrisense.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent

class AgriWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) renderOne(context, appWidgetManager, id)
        RefreshWorker.enqueueOnce(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        // Resizing re-renders instantly from the cached snapshot; no network needed.
        renderOne(context, appWidgetManager, appWidgetId)
    }

    override fun onEnabled(context: Context) {
        RefreshWorker.schedulePeriodic(context)
    }

    override fun onDisabled(context: Context) {
        RefreshWorker.cancelPeriodic(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (id in appWidgetIds) WidgetPrefs.delete(context, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            updateAll(context)
            RefreshWorker.enqueueOnce(context)
        }
    }

    companion object {
        const val ACTION_REFRESH = "com.agrisense.app.ACTION_REFRESH"

        private fun renderOne(ctx: Context, mgr: AppWidgetManager, id: Int) {
            try {
                mgr.updateAppWidget(id, WidgetRenderer.buildFor(ctx, mgr, id))
            } catch (e: Throwable) {
                // never show "can't load widget": fall back to a plain, always-valid view
                try {
                    val v = android.widget.RemoteViews(ctx.packageName, R.layout.widget_stack)
                    v.setTextViewText(R.id.val_status, "AgriSense")
                    mgr.updateAppWidget(id, v)
                } catch (_: Throwable) {
                }
            }
        }

        private fun ids(ctx: Context, mgr: AppWidgetManager): IntArray =
            mgr.getAppWidgetIds(ComponentName(ctx, AgriWidgetProvider::class.java))

        fun updateAll(ctx: Context) {
            val app = ctx.applicationContext
            val mgr = AppWidgetManager.getInstance(app)
            for (id in ids(app, mgr)) renderOne(app, mgr, id)
        }

        fun count(ctx: Context): Int {
            val app = ctx.applicationContext
            return ids(app, AppWidgetManager.getInstance(app)).size
        }

        fun renderWidget(ctx: Context, id: Int) {
            val app = ctx.applicationContext
            renderOne(app, AppWidgetManager.getInstance(app), id)
        }
    }
}

/** Single place to push a changed snapshot to every surface. */
object Updater {
    fun onChanged(ctx: Context) {
        AgriWidgetProvider.updateAll(ctx)
        LiveService.notifyIfRunning(ctx)
    }
}
