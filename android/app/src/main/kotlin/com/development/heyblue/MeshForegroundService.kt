package com.development.heyblue

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Foreground service for continuous mesh operation
 * Keeps the app running in background for BLE mesh networking
 * Also handles SOS alert notifications when packets are received
 */
class MeshForegroundService : Service(), SOSPacketCallback {

    companion object {
        private const val TAG = "MeshForegroundService"
        private const val SERVICE_NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "mesh_sos_channel"
        private const val CHANNEL_NAME = "Mesh SOS Service"

        // SOS Alert notification channel
        private const val SOS_ALERT_CHANNEL_ID = "sos_alert_channel"
        private const val SOS_ALERT_CHANNEL_NAME = "SOS Emergency Alerts"

        // SOS Status codes (must match sos_status.dart)
        private const val STATUS_SAFE = 0
        private const val STATUS_SOS = 1
        private const val STATUS_MEDICAL = 2
        private const val STATUS_TRAPPED = 3
        private const val STATUS_SUPPLIES = 4

        // Packet header
        private const val PACKET_HEADER = 0xFFFF
    }

    private var bleManager: BLEManager? = null
    private var notificationManager: NotificationManager? = null

    // Track notified packets to avoid duplicates (userId + sequence)
    private val notifiedPackets = mutableSetOf<String>()
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "MeshForegroundService created")
        notificationManager = getSystemService(NotificationManager::class.java)
        bleManager = BLEManager(this)
        bleManager?.setSOSPacketCallback(this)
        createNotificationChannels()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "MeshForegroundService started")
        
        val notification = createNotification()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                SERVICE_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(SERVICE_NOTIFICATION_ID, notification)
        }
        
        // Start mesh scanning in background
        startMeshScanning()
        
        return START_STICKY
    }
    
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Service channel (low priority, silent)
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps mesh SOS running in background"
                setShowBadge(false)
            }

            // SOS Alert channel (high priority, with sound and vibration)
            val sosAlertChannel = NotificationChannel(
                SOS_ALERT_CHANNEL_ID,
                SOS_ALERT_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Emergency SOS signal alerts from nearby devices"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 250, 500, 250, 500)
                enableLights(true)
                lightColor = Color.RED
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }

            notificationManager?.createNotificationChannel(serviceChannel)
            notificationManager?.createNotificationChannel(sosAlertChannel)
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
        bleManager?.setSOSPacketCallback(null)
        bleManager?.stopAll()
        notifiedPackets.clear()
        Log.d(TAG, "MeshForegroundService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // =====================
    // SOSPacketCallback Implementation
    // =====================

    override fun onSOSPacketReceived(packetData: ByteArray, rssi: Int) {
        Log.d(TAG, "SOS packet received in background service, size: ${packetData.size}, RSSI: $rssi")

        // Validate packet size (25 bytes expected)
        if (packetData.size < 21) {
            Log.w(TAG, "Packet too small: ${packetData.size} bytes")
            return
        }

        try {
            parseAndNotify(packetData, rssi)
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing SOS packet: ${e.message}")
        }
    }

    private fun parseAndNotify(packetData: ByteArray, rssi: Int) {
        val buffer = ByteBuffer.wrap(packetData).order(ByteOrder.BIG_ENDIAN)

        // Parse packet structure (25 bytes):
        // Bytes 0-1: Header (0xFFFF)
        // Bytes 2-5: User ID (4 bytes)
        // Bytes 6-7: Sequence number
        // Bytes 8-11: Latitude x 10^7
        // Bytes 12-15: Longitude x 10^7
        // Byte 16: Status code
        // Bytes 17-20: Unix timestamp
        // Bytes 21-24: Target ID (optional)

        val header = buffer.short.toInt() and 0xFFFF
        if (header != PACKET_HEADER) {
            Log.w(TAG, "Invalid packet header: $header")
            return
        }

        val userId = buffer.int
        val sequence = buffer.short.toInt() and 0xFFFF
        val latitudeE7 = buffer.int
        val longitudeE7 = buffer.int
        val status = buffer.get().toInt() and 0xFF

        // Don't notify for SAFE status
        if (status == STATUS_SAFE) {
            Log.d(TAG, "Received SAFE status from user $userId, not notifying")
            return
        }

        // Check for duplicate (userId + sequence)
        val packetKey = "${userId}_${sequence}"
        if (notifiedPackets.contains(packetKey)) {
            Log.d(TAG, "Already notified for packet: $packetKey")
            return
        }

        // Add to notified set (limit size to prevent memory issues)
        notifiedPackets.add(packetKey)
        if (notifiedPackets.size > 500) {
            // Remove oldest entries (first 100)
            val iterator = notifiedPackets.iterator()
            repeat(100) {
                if (iterator.hasNext()) {
                    iterator.next()
                    iterator.remove()
                }
            }
        }

        // Convert coordinates
        val latitude = latitudeE7 / 10_000_000.0
        val longitude = longitudeE7 / 10_000_000.0

        // Calculate approximate distance from RSSI
        val distance = calculateDistanceFromRssi(rssi)

        Log.d(TAG, "SOS Alert: User $userId, Status $status, Location ($latitude, $longitude), Distance: ${distance}m")

        showSOSNotification(userId, status, latitude, longitude, distance)
    }

    private fun calculateDistanceFromRssi(rssi: Int): String {
        // Path loss formula: d = 10^((MeasuredPower - RSSI) / (10 * N))
        // Using measured power = -69 dBm at 1 meter, N = 3.0 (disaster average)
        val measuredPower = -69.0
        val n = 3.0
        val distance = Math.pow(10.0, (measuredPower - rssi) / (10 * n))

        return when {
            distance < 2 -> "Very Close (<2m)"
            distance < 5 -> "Close (~${distance.toInt()}m)"
            distance < 10 -> "Nearby (~${distance.toInt()}m)"
            distance < 50 -> "Medium (~${distance.toInt()}m)"
            distance < 100 -> "Far (~${distance.toInt()}m)"
            else -> "Very Far (>100m)"
        }
    }

    private fun showSOSNotification(userId: Int, status: Int, latitude: Double, longitude: Double, distance: String) {
        val (title, color) = when (status) {
            STATUS_SOS -> "Emergency SOS Signal" to Color.RED
            STATUS_MEDICAL -> "Medical Emergency" to Color.rgb(255, 105, 180) // Pink
            STATUS_TRAPPED -> "Person Trapped" to Color.rgb(255, 87, 34) // Deep Orange
            STATUS_SUPPLIES -> "Supplies Needed" to Color.rgb(255, 152, 0) // Orange
            else -> "Emergency Signal" to Color.RED
        }

        val locationText = "%.6f, %.6f".format(latitude, longitude)
        val bodyText = "Distance: $distance\nLocation: $locationText"

        // Create intent to open app when notification tapped
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("sos_user_id", userId)
            putExtra("sos_latitude", latitude)
            putExtra("sos_longitude", longitude)
            putExtra("sos_status", status)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            userId, // Use userId as request code for unique PendingIntents
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, SOS_ALERT_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("Distance: $distance")
            .setStyle(NotificationCompat.BigTextStyle().bigText(bodyText))
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setColor(color)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setVibrate(longArrayOf(0, 500, 250, 500, 250, 500))
            .setDefaults(NotificationCompat.DEFAULT_SOUND)
            .build()

        // Use positive notification ID based on userId
        val notificationId = 2000 + (userId and 0x7FFFFFFF) % 1000
        notificationManager?.notify(notificationId, notification)

        // Also trigger vibration manually for emphasis
        triggerVibration()

        Log.d(TAG, "SOS notification shown for user $userId")
    }

    private fun triggerVibration() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(VibratorManager::class.java)
                vibratorManager?.defaultVibrator?.vibrate(
                    VibrationEffect.createWaveform(longArrayOf(0, 500, 250, 500, 250, 500), -1)
                )
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Vibrator::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(
                        VibrationEffect.createWaveform(longArrayOf(0, 500, 250, 500, 250, 500), -1)
                    )
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(longArrayOf(0, 500, 250, 500, 250, 500), -1)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error triggering vibration: ${e.message}")
        }
    }
}
