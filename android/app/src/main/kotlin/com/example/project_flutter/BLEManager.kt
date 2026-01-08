package com.example.project_flutter

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
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

        currentPacketData = packetData
        
        // Setup GATT server first
        setupGattServer()

        // Build advertising settings
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .setTimeout(0) // Advertise indefinitely
            .build()

        // Build advertising data
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()

        try {
            advertiser.startAdvertising(settings, data, advertiseCallback)
            isAdvertising = true
            updateCurrentState()
            Log.d(TAG, "Started advertising")
            return true
        } catch (e: Exception) {
            sendEvent("error", "Failed to start advertising: ${e.message}")
            return false
        }
    }

    fun stopBroadcasting(): Boolean {
        try {
            bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
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
            Log.d(TAG, "Advertising started successfully")
        }

        override fun onStartFailure(errorCode: Int) {
            isAdvertising = false
            updateCurrentState()
            sendEvent("error", "Advertising failed with code: $errorCode")
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

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

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
}
