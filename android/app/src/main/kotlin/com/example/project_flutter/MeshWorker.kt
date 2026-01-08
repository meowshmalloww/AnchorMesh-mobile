package com.example.project_flutter

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.*
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Background Worker for BLE Mesh SOS
 * 
 * Runs every 15 minutes to:
 * 1. Check USGS earthquake API
 * 2. Ping Google to verify internet
 * 3. Auto-activate mesh if disaster detected
 */
class MeshWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "MeshWorker"
        private const val WORK_NAME = "mesh_background_check"
        
        // USGS significant earthquakes API
        private const val USGS_API = 
            "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/significant_hour.geojson"
        
        /**
         * Schedule the background worker
         */
        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val workRequest = PeriodicWorkRequestBuilder<MeshWorker>(
                15, TimeUnit.MINUTES
            )
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.LINEAR,
                    10, TimeUnit.MINUTES
                )
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                workRequest
            )

            Log.d(TAG, "Background worker scheduled")
        }

        /**
         * Cancel the background worker
         */
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            Log.d(TAG, "Background worker cancelled")
        }
    }

    override suspend fun doWork(): Result {
        Log.d(TAG, "Background check started")

        try {
            // 1. Check for earthquakes
            val hasDisaster = checkUSGS()
            
            // 2. Check internet connectivity
            val hasInternet = pingGoogle()

            if (hasDisaster || !hasInternet) {
                Log.d(TAG, "Alert condition: disaster=$hasDisaster, internet=$hasInternet")
                // Notify the app to activate mesh mode
                // This would trigger via SharedPreferences flag or broadcast
                setAlertFlag(true)
            } else {
                setAlertFlag(false)
            }

            return Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Background check failed", e)
            return Result.retry()
        }
    }

    private fun checkUSGS(): Boolean {
        return try {
            val url = URL(USGS_API)
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 10000
            connection.readTimeout = 10000
            
            val response = connection.inputStream.bufferedReader().readText()
            connection.disconnect()
            
            // Check if there are any significant earthquakes
            // A proper implementation would parse the JSON
            response.contains("\"mag\":")
        } catch (e: Exception) {
            Log.e(TAG, "USGS check failed", e)
            false
        }
    }

    private fun pingGoogle(): Boolean {
        return try {
            val url = URL("https://www.google.com")
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 5000
            connection.requestMethod = "HEAD"
            connection.connect()
            val success = connection.responseCode == 200
            connection.disconnect()
            success
        } catch (e: Exception) {
            false
        }
    }

    private fun setAlertFlag(alert: Boolean) {
        val prefs = applicationContext.getSharedPreferences("mesh_sos", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("disaster_alert", alert).apply()
    }
}

/**
 * Boot receiver to start worker after phone restart
 */
class BootReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == android.content.Intent.ACTION_BOOT_COMPLETED) {
            context?.let { MeshWorker.schedule(it) }
        }
    }
}
