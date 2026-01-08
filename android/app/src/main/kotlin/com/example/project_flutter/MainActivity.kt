package com.example.project_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var blePeripheralHandler: BLEPeripheralHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register BLE Peripheral Handler for SOS mesh networking
        blePeripheralHandler = BLEPeripheralHandler(this)
        blePeripheralHandler?.registerWithEngine(flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        blePeripheralHandler?.unregister()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
