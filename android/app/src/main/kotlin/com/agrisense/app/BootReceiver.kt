package com.agrisense.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val a = intent.action
        if (a != Intent.ACTION_BOOT_COMPLETED && a != Intent.ACTION_MY_PACKAGE_REPLACED) return
        try {
            AgriWidgetProvider.updateAll(context)
            if (AgriWidgetProvider.count(context) > 0 || Notify.enabled(context)) {
                RefreshWorker.schedulePeriodic(context)
                RefreshWorker.enqueueOnce(context)
            }
            if (Live.enabled(context) || Notify.instantActive(context)) LiveService.start(context)
        } catch (e: Exception) {
            // ignore
        }
    }
}
