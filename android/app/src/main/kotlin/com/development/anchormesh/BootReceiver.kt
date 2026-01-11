package com.development.anchormesh

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Boot receiver to start mesh service on device boot
 */
class BootReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "BootReceiver"
    }
    
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d(TAG, "Boot completed - scheduling mesh worker")
            
            context?.let { ctx ->
                // Schedule WorkManager task for periodic mesh scanning
                MeshWorker.schedulePeriodicWork(ctx)
                
                // Start foreground service for continuous operation
                val serviceIntent = Intent(ctx, MeshForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    try {
                        ctx.startForegroundService(serviceIntent)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start foreground service from boot: ${e.message}")
                        // Fallback: WorkManager (already scheduled above) will handle it eventually
                    }
                } else {
                    ctx.startService(serviceIntent)
                }
            }
        }
    }
}
