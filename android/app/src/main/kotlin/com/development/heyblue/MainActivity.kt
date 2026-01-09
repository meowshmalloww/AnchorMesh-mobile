package com.development.heyblue

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var bleManager: BLEManager
    private lateinit var nativeThemeHandler: NativeThemeHandler
    private val METHOD_CHANNEL = "com.project_flutter/ble"
    private val EVENT_CHANNEL = "com.project_flutter/ble_events"

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1001
    }

    // Pending result for notification permission request
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        bleManager = BLEManager(this)
        nativeThemeHandler = NativeThemeHandler(this)

        // Setup Liquid Glass / Material You channels
        setupNativeThemeChannels(flutterEngine)

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
                    "supportsAdvertising" -> {
                        result.success(bleManager.supportsAdvertising())
                    }
                    "writePacketToRelay" -> {
                        val packetBytes = call.argument<List<Int>>("packet")
                        if (packetBytes != null) {
                            val byteArray = packetBytes.map { it.toByte() }.toByteArray()
                            result.success(bleManager.writePacketToRelay(byteArray))
                        } else {
                            result.error("INVALID_ARGS", "Missing packet data", null)
                        }
                    }
                    "checkWifiStatus" -> {
                        result.success(bleManager.checkWifiStatus())
                    }
                    "applyAndroidNativeTheme" -> {
                        val themeId = call.argument<String>("themeId")
                        result.success(bleManager.applyAndroidNativeTheme(themeId))
                    }
                    "startBackgroundMonitoring" -> {
                        val serviceIntent = Intent(this, MeshForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    }
                    "stopBackgroundMonitoring" -> {
                        val serviceIntent = Intent(this, MeshForegroundService::class.java)
                        stopService(serviceIntent)
                        result.success(true)
                    }
                    "hasNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val granted = ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED
                            result.success(granted)
                        } else {
                            // Pre-Android 13, notifications are allowed by default
                            result.success(true)
                        }
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            if (ContextCompat.checkSelfPermission(
                                    this,
                                    Manifest.permission.POST_NOTIFICATIONS
                                ) == PackageManager.PERMISSION_GRANTED
                            ) {
                                result.success(true)
                            } else {
                                pendingNotificationPermissionResult = result
                                ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    NOTIFICATION_PERMISSION_REQUEST_CODE
                                )
                            }
                        } else {
                            result.success(true)
                        }
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationPermissionResult?.success(granted)
            pendingNotificationPermissionResult = null
        }
    }

    private fun setupNativeThemeChannels(flutterEngine: FlutterEngine) {
        // Method channel for Liquid Glass / Material You
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeThemeHandler.METHOD_CHANNEL
        ).setMethodCallHandler(nativeThemeHandler)

        // Event channel for theme change notifications
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeThemeHandler.EVENT_CHANNEL
        ).setStreamHandler(nativeThemeHandler)
    }
}
