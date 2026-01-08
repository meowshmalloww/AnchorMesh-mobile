package com.example.project_flutter

import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.*

/**
 * BLE Peripheral Handler for Android
 * Implements advertising and GATT server for SOS mesh networking
 */
class BLEPeripheralHandler(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        // Service and Characteristic UUIDs
        // Using "505" to look like "SOS" in Hex
        val SOS_SERVICE_UUID: UUID = UUID.fromString("00005050-0000-1000-8000-00805f9b34fb")
        val SOS_ALERT_CHAR_UUID: UUID = UUID.fromString("00005051-0000-1000-8000-00805f9b34fb")
        val DEVICE_INFO_CHAR_UUID: UUID = UUID.fromString("00005052-0000-1000-8000-00805f9b34fb")
        val ACK_CHAR_UUID: UUID = UUID.fromString("00005053-0000-1000-8000-00805f9b34fb")
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private val bluetoothManager: BluetoothManager? by lazy {
        context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    }

    private val bluetoothAdapter: BluetoothAdapter? by lazy {
        bluetoothManager?.adapter
    }

    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null

    private var isAdvertising = false
    private var currentAdvertisementData: ByteArray? = null
    private var localName: String = "SOS-Device"

    private val connectedDevices = mutableMapOf<String, BluetoothDevice>()
    private val mainHandler = Handler(Looper.getMainLooper())

    // GATT Characteristics
    private var sosAlertCharacteristic: BluetoothGattCharacteristic? = null

    /**
     * Register method and event channels with Flutter
     */
    fun registerWith(plugins: io.flutter.embedding.engine.plugins.PluginRegistry) {
        val messenger = (plugins as? io.flutter.embedding.engine.FlutterEngine)?.dartExecutor?.binaryMessenger
            ?: return

        methodChannel = MethodChannel(messenger, "com.sosapp/ble_peripheral")
        methodChannel?.setMethodCallHandler(this)

        eventChannel = EventChannel(messenger, "com.sosapp/ble_peripheral_events")
        eventChannel?.setStreamHandler(this)
    }

    /**
     * Alternative registration with FlutterEngine directly
     */
    fun registerWithEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        methodChannel = MethodChannel(messenger, "com.sosapp/ble_peripheral")
        methodChannel?.setMethodCallHandler(this)

        eventChannel = EventChannel(messenger, "com.sosapp/ble_peripheral_events")
        eventChannel?.setStreamHandler(this)
    }

    /**
     * Unregister channels
     */
    fun unregister() {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        stopAdvertising()
        gattServer?.close()
    }

    // EventChannel.StreamHandler implementation
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // MethodChannel.MethodCallHandler implementation
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(result)
            "startAdvertising" -> {
                val data = call.argument<ByteArray>("data")
                val serviceUuid = call.argument<String>("serviceUuid")
                val name = call.argument<String>("localName") ?: "SOS-Device"
                if (data != null) {
                    startAdvertising(data, serviceUuid, name, result)
                } else {
                    result.error("INVALID_ARGS", "Missing data", null)
                }
            }
            "updateAdvertisement" -> {
                val data = call.argument<ByteArray>("data")
                if (data != null) {
                    updateAdvertisement(data, result)
                } else {
                    result.error("INVALID_ARGS", "Missing data", null)
                }
            }
            "stopAdvertising" -> stopAdvertising(result)
            "sendData" -> {
                val deviceAddress = call.argument<String>("deviceAddress")
                val data = call.argument<ByteArray>("data")
                if (deviceAddress != null && data != null) {
                    sendData(deviceAddress, data, result)
                } else {
                    result.error("INVALID_ARGS", "Missing parameters", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        val adapter = bluetoothAdapter
        if (adapter == null) {
            result.success(mapOf("supported" to false, "reason" to "No Bluetooth adapter"))
            return
        }

        if (!adapter.isMultipleAdvertisementSupported) {
            result.success(mapOf("supported" to false, "reason" to "BLE advertising not supported"))
            return
        }

        bluetoothLeAdvertiser = adapter.bluetoothLeAdvertiser
        if (bluetoothLeAdvertiser == null) {
            result.success(mapOf("supported" to false, "reason" to "BLE advertiser not available"))
            return
        }

        // Setup GATT server
        setupGattServer()

        result.success(mapOf("supported" to true, "state" to adapter.state))
    }

    private fun setupGattServer() {
        try {
            gattServer = bluetoothManager?.openGattServer(context, gattServerCallback)

            // Create SOS Alert Characteristic
            sosAlertCharacteristic = BluetoothGattCharacteristic(
                SOS_ALERT_CHAR_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ or
                        BluetoothGattCharacteristic.PROPERTY_WRITE or
                        BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ or
                        BluetoothGattCharacteristic.PERMISSION_WRITE
            )

            // Create Device Info Characteristic
            val deviceInfoChar = BluetoothGattCharacteristic(
                DEVICE_INFO_CHAR_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ,
                BluetoothGattCharacteristic.PERMISSION_READ
            )

            // Create ACK Characteristic
            val ackChar = BluetoothGattCharacteristic(
                ACK_CHAR_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                        BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_WRITE
            )

            // Add Client Characteristic Configuration Descriptor for notifications
            val cccd = BluetoothGattDescriptor(
                UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"),
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
            )
            sosAlertCharacteristic?.addDescriptor(cccd)
            ackChar.addDescriptor(cccd)

            // Create and add service
            val sosService = BluetoothGattService(
                SOS_SERVICE_UUID,
                BluetoothGattService.SERVICE_TYPE_PRIMARY
            )
            sosService.addCharacteristic(sosAlertCharacteristic)
            sosService.addCharacteristic(deviceInfoChar)
            sosService.addCharacteristic(ackChar)

            gattServer?.addService(sosService)
        } catch (e: SecurityException) {
            sendEvent(mapOf("type" to "advertisingError", "message" to "Bluetooth permission denied"))
        }
    }

    private fun startAdvertising(data: ByteArray, serviceUuid: String?, name: String, result: MethodChannel.Result) {
        val advertiser = bluetoothLeAdvertiser
        if (advertiser == null) {
            result.error("NOT_READY", "BLE advertiser not available", null)
            return
        }

        try {
            // Stop any existing advertising
            if (isAdvertising) {
                advertiser.stopAdvertising(advertiseCallback)
            }

            currentAdvertisementData = data
            localName = name

            // Update characteristic value
            sosAlertCharacteristic?.value = data

            // Build advertise settings
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(true)
                .setTimeout(0) // Advertise indefinitely
                .build()

            // Build advertise data
            val advertiseData = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceUuid(ParcelUuid(SOS_SERVICE_UUID))
                .build()

            // Build scan response with service data
            // Legacy advertising max payload is 31 bytes.
            // Flags (3) + Service Data Header (4) + Data (21) = 28 bytes. Fits!
            val scanResponse = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .addServiceData(ParcelUuid(SOS_SERVICE_UUID), data.take(24).toByteArray()) 
                .build()

            advertiser.startAdvertising(settings, advertiseData, scanResponse, advertiseCallback)
            result.success(true)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Bluetooth permission denied", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun updateAdvertisement(data: ByteArray, result: MethodChannel.Result) {
        currentAdvertisementData = data

        // Update the characteristic value
        sosAlertCharacteristic?.value = data

        // Notify connected devices
        try {
            for ((_, device) in connectedDevices) {
                sosAlertCharacteristic?.let { char ->
                    gattServer?.notifyCharacteristicChanged(device, char, false)
                }
            }
            result.success(true)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Bluetooth permission denied", null)
        }
    }

    private fun stopAdvertising(result: MethodChannel.Result? = null) {
        try {
            bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
            isAdvertising = false
            currentAdvertisementData = null
            sendEvent(mapOf("type" to "advertisingStopped"))
            result?.success(null)
        } catch (e: SecurityException) {
            result?.error("PERMISSION_DENIED", "Bluetooth permission denied", null)
        }
    }

    private fun stopAdvertising() {
        stopAdvertising(null)
    }

    private fun sendData(deviceAddress: String, data: ByteArray, result: MethodChannel.Result) {
        val device = connectedDevices[deviceAddress]
        if (device == null) {
            result.success(false)
            return
        }

        try {
            sosAlertCharacteristic?.value = data
            val success = gattServer?.notifyCharacteristicChanged(device, sosAlertCharacteristic, false)
            result.success(success == true)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Bluetooth permission denied", null)
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            isAdvertising = true
            sendEvent(mapOf("type" to "advertisingStarted"))
        }

        override fun onStartFailure(errorCode: Int) {
            isAdvertising = false
            val message = when (errorCode) {
                ADVERTISE_FAILED_ALREADY_STARTED -> "Already advertising"
                ADVERTISE_FAILED_DATA_TOO_LARGE -> "Data too large"
                ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Feature unsupported"
                ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal error"
                ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many advertisers"
                else -> "Unknown error: $errorCode"
            }
            sendEvent(mapOf("type" to "advertisingError", "message" to message))
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
            device?.let {
                try {
                    when (newState) {
                        BluetoothProfile.STATE_CONNECTED -> {
                            connectedDevices[it.address] = it
                            sendEvent(mapOf(
                                "type" to "peerConnected",
                                "deviceAddress" to it.address
                            ))
                        }
                        BluetoothProfile.STATE_DISCONNECTED -> {
                            connectedDevices.remove(it.address)
                            sendEvent(mapOf(
                                "type" to "peerDisconnected",
                                "deviceAddress" to it.address
                            ))
                        }
                    }
                } catch (e: SecurityException) {
                    // Handle permission error
                }
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice?,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic?
        ) {
            try {
                when (characteristic?.uuid) {
                    SOS_ALERT_CHAR_UUID -> {
                        val data = currentAdvertisementData ?: ByteArray(0)
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, data)
                    }
                    DEVICE_INFO_CHAR_UUID -> {
                        val info = """{"platform":"android","version":"${Build.VERSION.RELEASE}"}""".toByteArray()
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, info)
                    }
                    else -> {
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, offset, null)
                    }
                }
            } catch (e: SecurityException) {
                // Handle permission error
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
            try {
                when (characteristic?.uuid) {
                    SOS_ALERT_CHAR_UUID, ACK_CHAR_UUID -> {
                        if (value != null) {
                            device?.let { dev ->
                                sendEvent(mapOf(
                                    "type" to "dataReceived",
                                    "deviceAddress" to dev.address,
                                    "characteristicUuid" to characteristic.uuid.toString(),
                                    "data" to value.toList()
                                ))

                                // Check if this is an SOS beacon
                                if (characteristic.uuid == SOS_ALERT_CHAR_UUID && value.size >= 22) {
                                    sendEvent(mapOf(
                                        "type" to "beaconReceived",
                                        "deviceAddress" to dev.address,
                                        "data" to value.toList(),
                                        "rssi" to -50 // We don't have RSSI for write requests
                                    ))
                                }
                            }
                        }

                        if (responseNeeded) {
                            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
                        }
                    }
                    else -> {
                        if (responseNeeded) {
                            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, offset, null)
                        }
                    }
                }
            } catch (e: SecurityException) {
                // Handle permission error
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice?,
            requestId: Int,
            descriptor: BluetoothGattDescriptor?,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            try {
                // Handle CCCD write for notifications
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
                }
            } catch (e: SecurityException) {
                // Handle permission error
            }
        }
    }

    private fun sendEvent(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }
}
