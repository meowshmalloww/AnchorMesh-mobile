package com.development.heyblue

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import java.net.HttpURLConnection
import java.net.URL
import java.util.*
import kotlin.concurrent.thread

/**
 * Callback interface for receiving SOS packets in background service
 */
interface SOSPacketCallback {
    fun onSOSPacketReceived(packetData: ByteArray, rssi: Int)
}

/**
 * BLE Manager for Android - Handles Bluetooth LE operations
 * Supports advertising (broadcaster) and scanning (observer) modes
 */
class BLEManager(private val context: Context) {

    companion object {
        private const val TAG = "BLEManager"

        // Custom service UUID for SOS mesh
        val SERVICE_UUID: UUID = UUID.fromString("12345678-1234-1234-1234-123456789ABC")

        // Characteristic UUID for SOS packet data (READ)
        val CHARACTERISTIC_UUID: UUID = UUID.fromString("12345678-1234-1234-1234-123456789ABD")

        // Characteristic UUID for relay write (WRITE) - for devices that can't advertise
        val WRITE_CHARACTERISTIC_UUID: UUID = UUID.fromString("12345678-1234-1234-1234-123456789ABE")

        // Target MTU for consistent packet size
        const val TARGET_MTU = 244

        // Max relay queue size
        const val MAX_RELAY_QUEUE_SIZE = 10
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

    // Background service callback for SOS notifications
    private var sosPacketCallback: SOSPacketCallback? = null

    // Track RSSI for devices during connection
    private val deviceRssiMap = mutableMapOf<String, Int>()

    // Relay queue for packets received via write (from non-advertising devices)
    private val relayQueue = mutableListOf<ByteArray>()

    // Pending packet to write to relay node (for devices that can't advertise)
    private var pendingWritePacket: ByteArray? = null

    init {
        bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
        bluetoothLeAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner
    }

    // =====================
    // Flutter Integration
    // =====================

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun setSOSPacketCallback(callback: SOSPacketCallback?) {
        sosPacketCallback = callback
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

        // Check if device supports BLE advertising (peripheral mode)
        val adapter = bluetoothAdapter
        if (adapter == null) {
            sendEvent("error", "Bluetooth not available on this device")
            return false
        }

        // Check if the chipset supports advertising
        // This is a hardware limitation - not all Bluetooth 4.0 chipsets support peripheral mode
        if (!adapter.isMultipleAdvertisementSupported) {
            Log.w(TAG, "BLE advertising not supported - device chipset does not support peripheral mode")
            sendEvent("error", "BLE advertising is not supported on this device. Your Bluetooth hardware does not support peripheral (advertising) mode. This feature requires a device with BLE 4.0+ peripheral support.")
            return false
        }

        val advertiser = bluetoothLeAdvertiser
        if (advertiser == null) {
            Log.w(TAG, "BluetoothLeAdvertiser is null despite isMultipleAdvertisementSupported=true")
            sendEvent("error", "BLE advertising not available. Please ensure Bluetooth is enabled.")
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

        // Try Extended Advertising features on Android O (API 26+)
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
                
                Log.d(TAG, "Attempting Extended Advertising (Coded PHY)...")
                return true

            } catch (e: Exception) {
                Log.w(TAG, "Extended Advertising failed or not supported: ${e.message}. Falling back to legacy.")
                // Fallback to legacy
            }
        }

        // Legacy Advertising Fallback
        return startLegacyAdvertising()
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
            if (advertisingSet != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                bluetoothLeAdvertiser?.stopAdvertisingSet(advertisingSetCallback)
                advertisingSet = null
            } else {
                bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
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

        // Read characteristic for broadcasting our SOS packet
        val readCharacteristic = BluetoothGattCharacteristic(
            CHARACTERISTIC_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        )

        // Write characteristic for receiving packets from non-advertising devices
        val writeCharacteristic = BluetoothGattCharacteristic(
            WRITE_CHARACTERISTIC_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )

        service.addCharacteristic(readCharacteristic)
        service.addCharacteristic(writeCharacteristic)
        gattServer?.addService(service)

        Log.d(TAG, "GATT server setup with read and write characteristics")
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
                // Serve our own packet OR the next packet from relay queue
                val data = getNextBroadcastPacket()
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

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice?,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic?,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            if (characteristic?.uuid == WRITE_CHARACTERISTIC_UUID && value != null) {
                // Received packet from a device that can't advertise - add to relay queue
                onRelayPacketReceived(value, device)
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
                }
            } else {
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
                }
            }
        }
    }

    /**
     * Get next packet to broadcast - alternates between own packet and relay queue
     */
    private var broadcastIndex = 0
    private fun getNextBroadcastPacket(): ByteArray {
        // Priority: own packet gets 50% of broadcasts, relay queue gets 50%
        broadcastIndex++

        if (broadcastIndex % 2 == 0 && currentPacketData != null) {
            return currentPacketData!!
        }

        if (relayQueue.isNotEmpty()) {
            val index = (broadcastIndex / 2) % relayQueue.size
            return relayQueue[index]
        }

        return currentPacketData ?: ByteArray(0)
    }

    /**
     * Handle packet received via write from non-advertising device
     */
    private fun onRelayPacketReceived(packetData: ByteArray, device: BluetoothDevice?) {
        // Validate packet (minimum size check)
        if (packetData.size < 17) {
            Log.w(TAG, "Relay packet too small: ${packetData.size} bytes")
            return
        }

        // Check if we already have this packet (by comparing first 8 bytes - userId + sequence)
        val packetKey = packetData.copyOfRange(0, 8).contentHashCode()
        val exists = relayQueue.any { it.copyOfRange(0, 8).contentHashCode() == packetKey }

        if (!exists) {
            // Add to relay queue
            relayQueue.add(packetData)

            // Enforce max queue size (FIFO)
            while (relayQueue.size > MAX_RELAY_QUEUE_SIZE) {
                relayQueue.removeAt(0)
            }

            Log.d(TAG, "Received relay packet from ${device?.address}, queue size: ${relayQueue.size}")

            // Send to Flutter for UI display
            sendEvent("packetReceived", packetData.toList())

            // Notify background service for notifications
            sosPacketCallback?.onSOSPacketReceived(packetData, -50) // Default RSSI for local write
        } else {
            Log.d(TAG, "Duplicate relay packet ignored from ${device?.address}")
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

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            result?.device?.let { device ->
                val address = device.address
                if (!discoveredDevices.contains(address)) {
                    discoveredDevices.add(address)
                    // Store RSSI for this device
                    deviceRssiMap[address] = result.rssi
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
            private var hasWrittenPacket = false
            private var hasReadPacket = false

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

                    // Read their packet first
                    val readCharacteristic = service?.getCharacteristic(CHARACTERISTIC_UUID)
                    if (readCharacteristic != null) {
                        gatt.readCharacteristic(readCharacteristic)
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
                        // Send to Flutter UI
                        sendEvent("packetReceived", data.toList())

                        // Also notify background service callback for notifications
                        val deviceAddress = gatt?.device?.address
                        val rssi = deviceRssiMap[deviceAddress] ?: -100
                        sosPacketCallback?.onSOSPacketReceived(data, rssi)

                        // Clean up RSSI tracking
                        deviceAddress?.let { deviceRssiMap.remove(it) }
                    }
                }
                hasReadPacket = true

                // If we have a pending packet and can't advertise, write it to this relay node
                val packetToWrite = pendingWritePacket
                if (packetToWrite != null && !supportsAdvertising() && !hasWrittenPacket) {
                    val service = gatt?.getService(SERVICE_UUID)
                    val writeCharacteristic = service?.getCharacteristic(WRITE_CHARACTERISTIC_UUID)
                    if (writeCharacteristic != null) {
                        writeCharacteristic.value = packetToWrite
                        writeCharacteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                        val writeStarted = gatt.writeCharacteristic(writeCharacteristic)
                        Log.d(TAG, "Writing packet to relay node ${device.address}: started=$writeStarted")
                    } else {
                        Log.w(TAG, "Relay node ${device.address} does not have write characteristic")
                        disconnectIfDone(gatt)
                    }
                } else {
                    disconnectIfDone(gatt)
                }
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt?,
                characteristic: BluetoothGattCharacteristic?,
                status: Int
            ) {
                hasWrittenPacket = true

                if (status == BluetoothGatt.GATT_SUCCESS && characteristic?.uuid == WRITE_CHARACTERISTIC_UUID) {
                    Log.d(TAG, "Successfully wrote packet to relay node ${device.address}")
                    sendEvent("relayWriteSuccess", mapOf(
                        "address" to device.address,
                        "success" to true
                    ))

                    // Clear pending packet after successful write
                    pendingWritePacket = null
                    sendEvent("relayMode", false)
                } else {
                    Log.w(TAG, "Failed to write packet to relay node ${device.address}, status: $status")
                    sendEvent("relayWriteSuccess", mapOf(
                        "address" to device.address,
                        "success" to false,
                        "error" to "Write failed with status $status"
                    ))
                }

                disconnectIfDone(gatt)
            }

            private fun disconnectIfDone(gatt: BluetoothGatt?) {
                // Disconnect if we've completed both read and write (or write not needed)
                val needsWrite = pendingWritePacket != null && !supportsAdvertising()
                if (hasReadPacket && (!needsWrite || hasWrittenPacket)) {
                    gatt?.disconnect()
                }
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
     * Check if device supports BLE advertising (peripheral mode)
     * Not all Bluetooth 4.0 chipsets support advertising - this is a hardware limitation
     */
    fun supportsAdvertising(): Boolean {
        val adapter = bluetoothAdapter ?: return false
        return adapter.isMultipleAdvertisementSupported
    }

    /**
     * Write packet to a relay node (for devices that can't advertise)
     * This allows non-advertising devices to still send SOS signals by:
     * 1. Scanning for nearby advertising devices
     * 2. Connecting to them
     * 3. Writing the SOS packet to the relay node
     * 4. The relay node broadcasts the packet
     */
    fun writePacketToRelay(packetData: ByteArray): Boolean {
        // If device can advertise, use normal broadcasting
        if (supportsAdvertising()) {
            Log.d(TAG, "Device supports advertising, using normal broadcast")
            return startBroadcasting(packetData)
        }

        Log.d(TAG, "Device cannot advertise - using write-to-relay mode")

        // Store packet for writing when we connect to a relay node
        pendingWritePacket = packetData
        sendEvent("relayMode", true)

        // Start scanning to find relay nodes
        if (!isScanning) {
            val scanStarted = startScanning()
            if (!scanStarted) {
                sendEvent("error", "Failed to start scanning for relay nodes")
                return false
            }
        }

        return true
    }

    /**
     * Check if there's a pending packet waiting to be relayed
     */
    fun hasPendingRelayPacket(): Boolean = pendingWritePacket != null

    /**
     * Clear the pending relay packet (after successful relay or manual cancel)
     */
    fun clearPendingRelayPacket() {
        pendingWritePacket = null
        sendEvent("relayMode", false)
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
     * Apply Android native theme elements (Mock implementation)
     */
    fun applyAndroidNativeTheme(themeId: String?): Boolean {
        Log.d(TAG, "Applying Android native theme: $themeId")
        // In a real implementation, this could trigger Material You color extraction
        // or dynamic theme changes in the Activity context.
        return true
    }
}
