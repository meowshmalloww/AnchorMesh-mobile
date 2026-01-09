package com.development.heyblue

import android.content.Context
import android.util.Log
import androidx.work.*
import java.util.concurrent.TimeUnit

/**
 * WorkManager worker for periodic mesh scanning
 * Runs every 15 minutes to check for and relay SOS signals
 */
class MeshWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {
    
    companion object {
        private const val TAG = "MeshWorker"
        private const val WORK_NAME = "mesh_sos_worker"
        private const val REPEAT_INTERVAL_MINUTES = 15L
        
        /**
         * Schedule periodic work for mesh scanning
         */
        fun schedulePeriodicWork(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiresBatteryNotLow(false) // Run even on low battery for emergencies
                .build()
            
            val workRequest = PeriodicWorkRequestBuilder<MeshWorker>(
                REPEAT_INTERVAL_MINUTES, TimeUnit.MINUTES
            )
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.LINEAR,
                    WorkRequest.MIN_BACKOFF_MILLIS,
                    TimeUnit.MILLISECONDS
                )
                .addTag(WORK_NAME)
                .build()
            
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                workRequest
            )
            
            Log.d(TAG, "Scheduled periodic mesh work every $REPEAT_INTERVAL_MINUTES minutes")
        }
        
        /**
         * Cancel scheduled work
         */
        fun cancelWork(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            Log.d(TAG, "Cancelled mesh work")
        }
        
        /**
         * Run one-time work immediately
         */
        fun runOnce(context: Context) {
            val workRequest = OneTimeWorkRequestBuilder<MeshWorker>()
                .addTag("${WORK_NAME}_once")
                .build()
            
            WorkManager.getInstance(context).enqueue(workRequest)
            Log.d(TAG, "Enqueued one-time mesh work")
        }
    }
    
    override fun doWork(): Result {
        Log.d(TAG, "MeshWorker starting...")
        
        return try {
            val bleManager = BLEManager(context)
            
            // Quick scan for 30 seconds
            val scanSuccessful = bleManager.startScanning()
            
            if (scanSuccessful) {
                // Let it scan for 30 seconds
                Thread.sleep(30000)
                bleManager.stopScanning()
                Log.d(TAG, "Mesh scan completed successfully")
            }
            
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "MeshWorker failed: ${e.message}")
            Result.retry()
        }
    }
}
