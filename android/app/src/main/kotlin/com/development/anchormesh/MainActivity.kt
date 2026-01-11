package com.development.anchormesh

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var bleManager: BLEManager
    private val METHOD_CHANNEL = "com.project_flutter/ble"
    private val EVENT_CHANNEL = "com.project_flutter/ble_events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        bleManager = BLEManager(this)

        // Setup method channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startBroadcasting" -> {
                        val packetBytes = call.argument<List<Int>>("packet")
                        val advertisingMode = call.argument<String>("advertisingMode") ?: "balanced"
                        val txPower = call.argument<String>("txPower") ?: "high"
                        if (packetBytes != null) {
                            val byteArray = packetBytes.map { it.toByte() }.toByteArray()
                            result.success(bleManager.startBroadcasting(byteArray, advertisingMode, txPower))
                        } else {
                            result.error("INVALID_ARGS", "Missing packet data", null)
                        }
                    }
                    "stopBroadcasting" -> {
                        result.success(bleManager.stopBroadcasting())
                    }
                    "startScanning" -> {
                        val scanMode = call.argument<String>("scanMode") ?: "balanced"
                        val useScanFilters = call.argument<Boolean>("useScanFilters") ?: true
                        result.success(bleManager.startScanning(scanMode, useScanFilters))
                    }
                    "stopScanning" -> {
                        result.success(bleManager.stopScanning())
                    }
                    "checkInternet" -> {
                        Thread {
                            val hasInternet = bleManager.checkInternet()
                            runOnUiThread { result.success(hasInternet) }
                        }.start()
                    }
                    "getDeviceUuid" -> {
                        result.success(bleManager.getDeviceUuid())
                    }
                    "getBluetoothState" -> {
                        result.success(bleManager.getBluetoothState())
                    }
                    "requestBluetoothEnable" -> {
                        result.success(bleManager.requestBluetoothEnable(this))
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        result.success(bleManager.requestBatteryOptimizationExemption())
                    }
                    "requestBatteryExemption" -> {
                        result.success(bleManager.requestBatteryOptimizationExemption())
                    }
                    "setAdvertisingMode" -> {
                        val mode = call.argument<String>("mode") ?: "balanced"
                        result.success(bleManager.setAdvertisingMode(mode))
                    }
                    "supportsBle5" -> {
                        result.success(bleManager.supportsBle5())
                    }
                    "checkWifiStatus" -> {
                        result.success(bleManager.checkWifiStatus())
                    }
                    "testNotification" -> {
                        // Simulate receiving an SOS packet for testing notifications
                        bleManager.testNotification()
                        result.success(true)
                    }
                    "startRawScan" -> {
                        result.success(bleManager.startRawScan())
                    }
                    "stopRawScan" -> {
                        result.success(bleManager.stopRawScan())
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }

        // Setup event channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    bleManager.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    bleManager.setEventSink(null)
                }
            })
    }

    override fun onDestroy() {
        super.onDestroy()
        bleManager.stopAll()
    }
}
