package com.development.heyblue

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
                        if (packetBytes != null) {
                            val byteArray = packetBytes.map { it.toByte() }.toByteArray()
                            result.success(bleManager.startBroadcasting(byteArray))
                        } else {
                            result.error("INVALID_ARGS", "Missing packet data", null)
                        }
                    }
                    "stopBroadcasting" -> {
                        result.success(bleManager.stopBroadcasting())
                    }
                    "startScanning" -> {
                        result.success(bleManager.startScanning())
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
                    "requestBatteryExemption" -> {
                        result.success(bleManager.requestBatteryOptimizationExemption())
                    }
                    "supportsBle5" -> {
                        result.success(bleManager.supportsBle5())
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
