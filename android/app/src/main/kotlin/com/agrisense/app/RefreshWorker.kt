package com.agrisense.app

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

class RefreshWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        try {
            Net.fetchAndStore(applicationContext)
            Updater.onChanged(applicationContext)
            EventNotifier.run(applicationContext)
        } catch (e: Exception) {
            return Result.retry()
        }
        return Result.success()
    }

    companion object {
        private const val PERIODIC = "agrisense_periodic_refresh"
        private const val ONCE = "agrisense_once_refresh"

        private fun net(): Constraints =
            Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

        fun schedulePeriodic(ctx: Context) {
            val req = PeriodicWorkRequest.Builder(RefreshWorker::class.java, 15, TimeUnit.MINUTES)
                .setConstraints(net())
                .build()
            WorkManager.getInstance(ctx.applicationContext)
                .enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.KEEP, req)
        }

        fun cancelPeriodic(ctx: Context) {
            WorkManager.getInstance(ctx.applicationContext).cancelUniqueWork(PERIODIC)
        }

        fun enqueueOnce(ctx: Context) {
            val req = OneTimeWorkRequest.Builder(RefreshWorker::class.java)
                .setConstraints(net())
                .build()
            WorkManager.getInstance(ctx.applicationContext)
                .enqueueUniqueWork(ONCE, ExistingWorkPolicy.REPLACE, req)
        }
    }
}
