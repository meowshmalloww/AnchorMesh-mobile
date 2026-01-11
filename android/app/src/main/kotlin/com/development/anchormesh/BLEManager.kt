package com.development.anchormesh

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import java.net.HttpURLConnection
import java.net.URL
import java.util.*
import kotlin.concurrent.thread

/**
 * BLE Manager for Android - Handles Bluetooth LE operations
 * Supports advertising (broadcaster) and scanning (observer) modes
 */
class BLEManager(private val context: Context) {

    companion object {
        private const val TAG = "BLEManager"

        // Custom service UUID for SOS mesh
        val SERVICE_UUID: UUID = UUID.fromString("12345678-1234-1234-1234-123456789ABC")

        // Characteristic UUID for SOS packet data
        val CHARACTERISTIC_UUID: UUID = UUID.fromString("12345678-1234-1234-1234-123456789ABD")

        // Target MTU for consistent packet size
        const val TARGET_MTU = 244

        // Notification channel for SOS alerts
        const val SOS_NOTIFICATION_CHANNEL_ID = "sos_alert_channel"
        const val SOS_NOTIFICATION_CHANNEL_NAME = "SOS Emergency Alerts"

        // Status codes from SOS packet (byte 16)
        const val STATUS_SAFE = 0x00
        const val STATUS_SOS = 0x01
        const val STATUS_MEDICAL = 0x02
        const val STATUS_TRAPPED = 0x03
        const val STATUS_SUPPLIES = 0x04
    }

    // Bluetooth components
    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var gattServer: BluetoothGattServer? = null

    // State
    private var isAdvertising = false
    private var isScanning = false
    private var currentPacketData: ByteArray? = null
    private val connectedDevices = mutableSetOf<BluetoothDevice>()
    private val discoveredDevices = mutableSetOf<String>()
    private val relayedPacketIds = mutableSetOf<String>()

    // Flutter event sink
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
        bluetoothLeAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner
        createNotificationChannel()
    }

    // =====================
    // Notification Setup
    // =====================

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(
                SOS_NOTIFICATION_CHANNEL_ID,
                SOS_NOTIFICATION_CHANNEL_NAME,
                importance
            ).apply {
                description = "Emergency SOS alerts from nearby devices"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setBypassDnd(true)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }
            val notificationManager = context.getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
            Log.d(TAG, "SOS notification channel created")
        }
    }

    private fun showSOSNotification(packetData: ByteArray) {
        // Parse packet to extract status (byte 16) and location
        if (packetData.size < 21) {
            Log.w(TAG, "Packet too small for notification: ${packetData.size}")
            return
        }

        val status = packetData[16].toInt() and 0xFF

        // Don't notify for SAFE status
        if (status == STATUS_SAFE) {
            Log.d(TAG, "Received SAFE status, no notification needed")
            return
        }

        // Extract lat/lon (bytes 8-15, stored as int * 10^7)
        val latE7 = ((packetData[8].toInt() and 0xFF) or
                    ((packetData[9].toInt() and 0xFF) shl 8) or
                    ((packetData[10].toInt() and 0xFF) shl 16) or
                    ((packetData[11].toInt() and 0xFF) shl 24))
        val lonE7 = ((packetData[12].toInt() and 0xFF) or
                    ((packetData[13].toInt() and 0xFF) shl 8) or
                    ((packetData[14].toInt() and 0xFF) shl 16) or
                    ((packetData[15].toInt() and 0xFF) shl 24))

        val lat = latE7 / 10000000.0
        val lon = lonE7 / 10000000.0

        // Get status text and emoji
        val (title, emoji) = when (status) {
            STATUS_SOS -> "EMERGENCY SOS" to "🆘"
            STATUS_MEDICAL -> "MEDICAL EMERGENCY" to "🏥"
            STATUS_TRAPPED -> "PERSON TRAPPED" to "🚨"
            STATUS_SUPPLIES -> "SUPPLIES NEEDED" to "📦"
            else -> "EMERGENCY ALERT" to "⚠️"
        }

        val notificationTitle = "$emoji $title"
        val notificationText = "Someone nearby needs help! Location: %.4f, %.4f".format(lat, lon)

        // Create intent to open app when notification is tapped
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        intent?.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        val pendingIntent = PendingIntent.getActivity(
            context,
            System.currentTimeMillis().toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, SOS_NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(notificationTitle)
            .setContentText(notificationText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(notificationText))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setVibrate(longArrayOf(0, 500, 200, 500, 200, 500))
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .build()

        // Check notification permission for Android 13+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
                Log.w(TAG, "Notification permission not granted")
                return
            }
        }

        try {
            NotificationManagerCompat.from(context).notify(
                System.currentTimeMillis().toInt(),
                notification
            )
            Log.d(TAG, "SOS notification shown: $title")

            // Also vibrate separately for extra alertness
            vibrateDevice()
        } catch (e: SecurityException) {
            Log.e(TAG, "Failed to show notification: ${e.message}")
        }
    }

    private fun vibrateDevice() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                val vibrator = vibratorManager?.defaultVibrator
                vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 500, 200, 500, 200, 500), -1))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 500, 200, 500, 200, 500), -1))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(longArrayOf(0, 500, 200, 500, 200, 500), -1)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to vibrate: ${e.message}")
        }
    }

    // =====================
    // Flutter Integration
    // =====================

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    private fun sendEvent(type: String, data: Any?) {
        mainHandler.post {
            eventSink?.success(mapOf("type" to type, "data" to data))
        }
    }

    private fun updateState(state: String) {
        sendEvent("stateChanged", state)
    }

    private fun updateCurrentState() {
        val state = when {
            isAdvertising && isScanning -> "meshActive"
            isAdvertising -> "broadcasting"
            isScanning -> "scanning"
            else -> "idle"
        }
        updateState(state)
    }

    // =====================
    // Broadcasting (Advertiser)
    // =====================

    private var advertisingSet: AdvertisingSet? = null
    
    // Callback for BLE 5.0 Extended Advertising
    private val advertisingSetCallback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        object : AdvertisingSetCallback() {
            override fun onAdvertisingSetStarted(advertisingSet: AdvertisingSet?, txPower: Int, status: Int) {
                if (status == AdvertisingSetCallback.ADVERTISE_SUCCESS) {
                    Log.d(TAG, "Extended Advertising started successfully. TxPower: $txPower")
                    this@BLEManager.advertisingSet = advertisingSet
                    isAdvertising = true
                    updateCurrentState()
                } else {
                    Log.e(TAG, "Extended Advertising failed to start: $status")
                    // Fallback to legacy if extended fails
                    startLegacyAdvertising()
                }
            }

            override fun onAdvertisingSetStopped(advertisingSet: AdvertisingSet?) {
                Log.d(TAG, "Extended Advertising stopped")
                isAdvertising = false
                updateCurrentState()
            }
        }
    } else null

    fun startBroadcasting(packetData: ByteArray): Boolean {
        if (!checkBluetoothPermissions()) {
            sendEvent("error", "Bluetooth permissions not granted")
            return false
        }

        val advertiser = bluetoothLeAdvertiser
        if (advertiser == null) {
            sendEvent("error", "BLE advertising not supported")
            return false
        }

        // Update packet data
        currentPacketData = packetData

        // If already advertising, update the data
        if (isAdvertising) {
            if (advertisingSet != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Update Extended Advertising data
                val data = AdvertiseData.Builder()
                    .setIncludeDeviceName(false)
                    .addServiceUuid(ParcelUuid(SERVICE_UUID))
                    .build()
                advertisingSet?.setAdvertisingData(data)
                Log.d(TAG, "Updated extended advertising data")
            }
            // For legacy, GATT server handles the data update automatically via read requests
            return true
        }

        // Setup GATT server first
        setupGattServer()

        // DUAL-MODE BROADCASTING: Run BOTH legacy and extended for cross-version compatibility
        // 1. Always start Legacy Advertising first (works with BLE 4.x AND 5.x devices)
        val legacyStarted = startLegacyAdvertising()
        
        // 2. Additionally start Extended Advertising if supported (for long range)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && supportsBle5()) {
            try {
                // Extended Advertising parameters (Long Range / Coded PHY)
                val parameters = AdvertisingSetParameters.Builder()
                    .setLegacyMode(false) // Use extended PDUs
                    .setConnectable(true)
                    .setInterval(AdvertisingSetParameters.INTERVAL_LOW)
                    .setTxPowerLevel(AdvertisingSetParameters.TX_POWER_HIGH)
                    .setPrimaryPhy(BluetoothDevice.PHY_LE_CODED) // Long Range
                    .setSecondaryPhy(BluetoothDevice.PHY_LE_CODED)
                    .build()

                val data = AdvertiseData.Builder()
                    .setIncludeDeviceName(false)
                    .addServiceUuid(ParcelUuid(SERVICE_UUID))
                    .build()

                advertiser.startAdvertisingSet(
                    parameters,
                    data,
                    null, // Scan response
                    null, // Periodic parameters
                    null, // Periodic data
                    advertisingSetCallback
                )
                
                Log.d(TAG, "Started DUAL-MODE: Legacy + Extended Advertising (Coded PHY)")

            } catch (e: Exception) {
                Log.w(TAG, "Extended Advertising failed: ${e.message}. Legacy-only mode.")
            }
        }

        return legacyStarted
    }

    private fun startLegacyAdvertising(): Boolean {
        val advertiser = bluetoothLeAdvertiser ?: return false
        
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .setTimeout(0) // Advertise indefinitely
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()

        try {
            advertiser.startAdvertising(settings, data, advertiseCallback)
            isAdvertising = true
            updateCurrentState()
            Log.d(TAG, "Started legacy advertising")
            return true
        } catch (e: Exception) {
            sendEvent("error", "Failed to start legacy advertising: ${e.message}")
            return false
        }
    }

    fun stopBroadcasting(): Boolean {
        try {
            // Stop Extended Advertising if active
            if (advertisingSet != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    bluetoothLeAdvertiser?.stopAdvertisingSet(advertisingSetCallback)
                } catch (e: Exception) {
                    Log.w(TAG, "Error stopping extended advertising: ${e.message}")
                }
                advertisingSet = null
            }
            
            // ALWAYS stop Legacy Advertising (since we always start it)
            try {
                bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
            } catch (e: Exception) {
                Log.w(TAG, "Error stopping legacy advertising: ${e.message}")
            }
            
            gattServer?.close()
            gattServer = null
            isAdvertising = false
            updateCurrentState()
            Log.d(TAG, "Stopped advertising")
            return true
        } catch (e: Exception) {
            sendEvent("error", "Failed to stop advertising: ${e.message}")
            return false
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            Log.d(TAG, "Legacy advertising started successfully")
        }

        override fun onStartFailure(errorCode: Int) {
            isAdvertising = false
            updateCurrentState()
            sendEvent("error", "Legacy advertising failed with code: $errorCode")
        }
    }

    private fun setupGattServer() {
        if (!checkBluetoothPermissions()) return

        gattServer = bluetoothManager?.openGattServer(context, gattServerCallback)

        val service = BluetoothGattService(
            SERVICE_UUID,
            BluetoothGattService.SERVICE_TYPE_PRIMARY
        )

        val characteristic = BluetoothGattCharacteristic(
            CHARACTERISTIC_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        )

        service.addCharacteristic(characteristic)
        gattServer?.addService(service)
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    device?.let { connectedDevices.add(it) }
                    sendEvent("connectedDevicesChanged", connectedDevices.size)
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    device?.let { connectedDevices.remove(it) }
                    sendEvent("connectedDevicesChanged", connectedDevices.size)
                }
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice?,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic?
        ) {
            if (characteristic?.uuid == CHARACTERISTIC_UUID) {
                val data = currentPacketData ?: ByteArray(0)
                gattServer?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    offset,
                    data.copyOfRange(offset, minOf(offset + 20, data.size))
                )
            } else {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
            }
        }
    }

    // =====================
    // Scanning (Observer)
    // =====================

    fun startScanning(): Boolean {
        if (!checkBluetoothPermissions()) {
            sendEvent("error", "Bluetooth permissions not granted")
            return false
        }

        val scanner = bluetoothLeScanner
        if (scanner == null) {
            sendEvent("error", "BLE scanning not supported")
            return false
        }

        // Configure scan settings
        val settingsBuilder = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            
        // Enable Extended Advertising / Coded PHY support if available
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && supportsBle5()) {
            settingsBuilder.setLegacy(false)
            settingsBuilder.setPhy(ScanSettings.PHY_LE_ALL_SUPPORTED)
            Log.d(TAG, "Configured scanner for Extended Advertising (Coded PHY)")
        }

        val settings = settingsBuilder.build()

        val filters = listOf(
            ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(SERVICE_UUID))
                .build()
        )

        try {
            scanner.startScan(filters, settings, scanCallback)
            isScanning = true
            updateCurrentState()
            Log.d(TAG, "Started scanning")
            return true
        } catch (e: Exception) {
            sendEvent("error", "Failed to start scanning: ${e.message}")
            return false
        }
    }

    fun stopScanning(): Boolean {
        try {
            bluetoothLeScanner?.stopScan(scanCallback)
            isScanning = false
            updateCurrentState()
            Log.d(TAG, "Stopped scanning")
            return true
        } catch (e: Exception) {
            sendEvent("error", "Failed to stop scanning: ${e.message}")
            return false
        }
    }

    // =====================
    // RAW BLE Scanner (like nRF Connect)
    // =====================
    
    private var isRawScanning = false
    private val rawScanResults = mutableMapOf<String, Map<String, Any?>>()
    
    private val rawScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            result?.let { scanResult ->
                val device = scanResult.device
                val address = device.address
                val rssi = scanResult.rssi
                
                @Suppress("MissingPermission")
                val name = device.name ?: "Unknown"
                
                // Extract manufacturer data if available
                val manufacturerData = scanResult.scanRecord?.manufacturerSpecificData
                val mfgDataList = mutableListOf<Map<String, Any>>()
                manufacturerData?.let { data ->
                    for (i in 0 until data.size()) {
                        val key = data.keyAt(i)
                        val value = data.valueAt(i)
                        mfgDataList.add(mapOf("id" to key, "data" to value.toList()))
                    }
                }
                
                // Check if this is our SOS service
                val serviceUuids = scanResult.scanRecord?.serviceUuids?.map { it.uuid.toString() } ?: emptyList()
                val isSOS = serviceUuids.contains(SERVICE_UUID.toString())
                
                val deviceInfo = mapOf(
                    "address" to address,
                    "name" to name,
                    "rssi" to rssi,
                    "isSOS" to isSOS,
                    "serviceUuids" to serviceUuids,
                    "manufacturerData" to mfgDataList,
                    "txPower" to (scanResult.scanRecord?.txPowerLevel ?: -127)
                )
                
                rawScanResults[address] = deviceInfo
                sendEvent("rawDeviceFound", deviceInfo)
            }
        }

        override fun onScanFailed(errorCode: Int) {
            isRawScanning = false
            sendEvent("error", "Raw scan failed with code: $errorCode")
        }
    }
    
    fun startRawScan(): Boolean {
        if (!checkBluetoothPermissions()) {
            sendEvent("error", "Bluetooth permissions not granted")
            return false
        }

        val scanner = bluetoothLeScanner
        if (scanner == null) {
            sendEvent("error", "BLE scanner not available")
            return false
        }

        if (isRawScanning) return true
        
        rawScanResults.clear()

        val settingsBuilder = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setReportDelay(0)

        // Enable extended scan on BLE 5.0 devices
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && supportsBle5()) {
            settingsBuilder.setLegacy(false)
            settingsBuilder.setPhy(ScanSettings.PHY_LE_ALL_SUPPORTED)
        }

        val settings = settingsBuilder.build()

        try {
            // No filters - scan for ALL devices
            scanner.startScan(null, settings, rawScanCallback)
            isRawScanning = true
            Log.d(TAG, "Started raw BLE scan (all devices)")
            return true
        } catch (e: Exception) {
            sendEvent("error", "Failed to start raw scan: ${e.message}")
            return false
        }
    }
    
    fun stopRawScan(): Boolean {
        try {
            bluetoothLeScanner?.stopScan(rawScanCallback)
            isRawScanning = false
            Log.d(TAG, "Stopped raw BLE scan")
            return true
        } catch (e: Exception) {
            sendEvent("error", "Failed to stop raw scan: ${e.message}")
            return false
        }
    }


    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            result?.device?.let { device ->
                val address = device.address
                if (!discoveredDevices.contains(address)) {
                    discoveredDevices.add(address)
                    connectToDevice(device)
                }
            }
        }

        override fun onScanFailed(errorCode: Int) {
            isScanning = false
            updateCurrentState()
            sendEvent("error", "Scan failed with code: $errorCode")
        }
    }

    private fun connectToDevice(device: BluetoothDevice) {
        if (!checkBluetoothPermissions()) return

        device.connectGatt(context, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    gatt?.requestMtu(TARGET_MTU)
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    gatt?.close()
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    gatt?.discoverServices()
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    val service = gatt?.getService(SERVICE_UUID)
                    val characteristic = service?.getCharacteristic(CHARACTERISTIC_UUID)
                    if (characteristic != null) {
                        gatt.readCharacteristic(characteristic)
                    }
                }
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt?,
                characteristic: BluetoothGattCharacteristic?,
                status: Int
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS && characteristic?.uuid == CHARACTERISTIC_UUID) {
                    characteristic.value?.let { data ->
                        sendEvent("packetReceived", data.toList())
                        // Show native notification for SOS alert
                        showSOSNotification(data)
                    }
                }
                gatt?.disconnect()
            }
        })
    }

    // =====================
    // Utility Methods
    // =====================

    fun checkInternet(): Boolean {
        return try {
            thread {
                val connection = URL("https://www.google.com").openConnection() as HttpURLConnection
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                connection.connect()
                connection.responseCode == 200
            }.join()
            true
        } catch (e: Exception) {
            false
        }
    }

    fun getDeviceUuid(): String {
        return Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            ?: UUID.randomUUID().toString()
    }

    fun requestBatteryOptimizationExemption(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            context.startActivity(intent)
            return true
        }
        return false
    }

    private fun checkBluetoothPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED &&
                   ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
                   ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        }
        return true // Older versions use manifest permissions
    }

    fun stopAll() {
        stopBroadcasting()
        stopScanning()
        discoveredDevices.clear()
        connectedDevices.clear()
    }

    /**
     * Check if device supports BLE 5.0 features
     * BLE 5.0 requires Android 8.0 (API 26)+ and hardware support
     */
    fun supportsBle5(): Boolean {
        // BLE 5.0 features require Android 8.0 (API 26) minimum
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }

        val adapter = bluetoothAdapter ?: return false

        // Check for BLE 5.0 specific features
        // LE 2M PHY - higher throughput
        val supports2MPhy = adapter.isLe2MPhySupported
        // LE Coded PHY - longer range
        val supportsCodedPhy = adapter.isLeCodedPhySupported
        // Extended advertising
        val supportsExtendedAdvertising = adapter.isLeExtendedAdvertisingSupported

        // Device supports BLE 5 if it has at least one of the key features
        return supports2MPhy || supportsCodedPhy || supportsExtendedAdvertising
    }

    /**
     * Check if WiFi is enabled (potential interference)
     */
    fun checkWifiStatus(): Boolean {
        val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        return wifiManager?.isWifiEnabled == true
    }

    /**
     * Test notification by simulating an SOS packet reception
     * Creates a fake packet with test coordinates and triggers the notification
     */
    fun testNotification() {
        // Create a fake SOS packet (25 bytes)
        // Format: [header 2B][userId 4B][seq 2B][lat 4B][lon 4B][status 1B][timestamp 4B][targetId 4B]
        val testPacket = ByteArray(25)

        // Header: 0xFFFF
        testPacket[0] = 0xFF.toByte()
        testPacket[1] = 0xFF.toByte()

        // User ID: 0x12345678
        testPacket[2] = 0x78.toByte()
        testPacket[3] = 0x56.toByte()
        testPacket[4] = 0x34.toByte()
        testPacket[5] = 0x12.toByte()

        // Sequence: 1
        testPacket[6] = 0x01
        testPacket[7] = 0x00

        // Latitude: 37.7749 * 10^7 = 377749000 (San Francisco)
        val lat = 377749000
        testPacket[8] = (lat and 0xFF).toByte()
        testPacket[9] = ((lat shr 8) and 0xFF).toByte()
        testPacket[10] = ((lat shr 16) and 0xFF).toByte()
        testPacket[11] = ((lat shr 24) and 0xFF).toByte()

        // Longitude: -122.4194 * 10^7 = -1224194000
        val lon = -1224194000
        testPacket[12] = (lon and 0xFF).toByte()
        testPacket[13] = ((lon shr 8) and 0xFF).toByte()
        testPacket[14] = ((lon shr 16) and 0xFF).toByte()
        testPacket[15] = ((lon shr 24) and 0xFF).toByte()

        // Status: SOS (0x01)
        testPacket[16] = STATUS_SOS.toByte()

        // Timestamp: current time
        val timestamp = (System.currentTimeMillis() / 1000).toInt()
        testPacket[17] = (timestamp and 0xFF).toByte()
        testPacket[18] = ((timestamp shr 8) and 0xFF).toByte()
        testPacket[19] = ((timestamp shr 16) and 0xFF).toByte()
        testPacket[20] = ((timestamp shr 24) and 0xFF).toByte()

        // Target ID: 0 (broadcast)
        testPacket[21] = 0x00
        testPacket[22] = 0x00
        testPacket[23] = 0x00
        testPacket[24] = 0x00

        Log.d(TAG, "Testing notification with simulated SOS packet")
        showSOSNotification(testPacket)
    }
}
