package com.development.heyblue

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service for continuous mesh operation
 * Keeps the app running in background for BLE mesh networking
 */
class MeshForegroundService : Service() {
    
    companion object {
        private const val TAG = "MeshForegroundService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "mesh_sos_channel"
        private const val CHANNEL_NAME = "Mesh SOS Service"
    }
    
    private var bleManager: BLEManager? = null
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "MeshForegroundService created")
        bleManager = BLEManager(this)
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "MeshForegroundService started")
        
        val notification = createNotification()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, 
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        
        // Start mesh scanning in background
        startMeshScanning()
        
        return START_STICKY
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps mesh SOS running in background"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Mesh SOS Active")
            .setContentText("Scanning for emergency signals")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
    
    private fun startMeshScanning() {
        bleManager?.startScanning()
        Log.d(TAG, "Mesh scanning started")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        bleManager?.stopAll()
        Log.d(TAG, "MeshForegroundService destroyed")
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
}
