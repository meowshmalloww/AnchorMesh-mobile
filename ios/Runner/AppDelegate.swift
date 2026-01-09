import Flutter
import UIKit
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate {

    private var bleEventChannel: FlutterEventChannel?
    private var platformChannel: FlutterMethodChannel?
    private var isChannelsSetup = false
    private var lowPowerModeObserver: NSObjectProtocol?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Reset state for fresh app launch (handles reopen after force quit)
        isChannelsSetup = false
        BLEManager.shared.reset()

        GeneratedPluginRegistrant.register(with: self)

        // Register background tasks safely
        do {
            BackgroundTaskManager.shared.registerTasks()
        } catch {
            print("Failed to register background tasks: \(error)")
        }

        // Setup BLE platform channels after a brief delay to ensure window is ready
        DispatchQueue.main.async { [weak self] in
            self?.setupChannelsIfNeeded()
        }

        // Schedule background refresh
        BackgroundTaskManager.shared.scheduleRefresh()

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func setupLowPowerModeObserver() {
        lowPowerModeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.notifyLowPowerModeChanged()
        }
    }
    
    private func notifyLowPowerModeChanged() {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        platformChannel?.invokeMethod("onLowPowerModeChanged", arguments: isLowPower)
    }

    private func setupChannelsIfNeeded() {
        guard !isChannelsSetup else { return }
        guard let controller = window?.rootViewController as? FlutterViewController else {
            // Retry after a short delay if window isn't ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.setupChannelsIfNeeded()
            }
            return
        }

        setupBLEChannels(controller: controller)
        setupPlatformChannel(controller: controller)
        isChannelsSetup = true
    }
    
    private func setupPlatformChannel(controller: FlutterViewController) {
        platformChannel = FlutterMethodChannel(
            name: "com.project_flutter/platform",
            binaryMessenger: controller.binaryMessenger
        )
        
        platformChannel?.setMethodCallHandler { [weak self] (call, result) in
            self?.handlePlatformMethodCall(call: call, result: result)
        }
    }
    
    private func handlePlatformMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Wrap in error handling to prevent crashes
        do {
            try handlePlatformMethodCallUnsafe(call: call, result: result)
        } catch {
            result(FlutterError(code: "NATIVE_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handlePlatformMethodCallUnsafe(call: FlutterMethodCall, result: @escaping FlutterResult) throws {
        switch call.method {
        case "isLowPowerModeEnabled":
            result(ProcessInfo.processInfo.isLowPowerModeEnabled)

        case "setScreenAlwaysOn":
            guard let args = call.arguments as? [String: Any],
                  let enabled = args["enabled"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing enabled parameter", details: nil))
                return
            }
            UIApplication.shared.isIdleTimerDisabled = enabled
            result(UIApplication.shared.isIdleTimerDisabled)
            
        case "registerBackgroundScan":
            guard let args = call.arguments as? [String: Any],
                  let serviceUUID = args["serviceUUID"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing serviceUUID", details: nil))
                return
            }
            // Store for background scanning - BLEManager handles this
            UserDefaults.standard.set(serviceUUID, forKey: "backgroundServiceUUID")
            result(true)
            
        case "saveStateForRestoration":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing state data", details: nil))
                return
            }
            // Save state for iOS state preservation
            UserDefaults.standard.set(args["isBroadcasting"], forKey: "restore_isBroadcasting")
            UserDefaults.standard.set(args["isScanning"], forKey: "restore_isScanning")
            if let lat = args["latitude"] as? Double {
                UserDefaults.standard.set(lat, forKey: "restore_latitude")
            }
            if let lon = args["longitude"] as? Double {
                UserDefaults.standard.set(lon, forKey: "restore_longitude")
            }
            if let status = args["status"] as? Int {
                UserDefaults.standard.set(status, forKey: "restore_status")
            }
            result(nil)
            
        case "restoreState":
            let isBroadcasting = UserDefaults.standard.bool(forKey: "restore_isBroadcasting")
            let isScanning = UserDefaults.standard.bool(forKey: "restore_isScanning")
            let latitude = UserDefaults.standard.double(forKey: "restore_latitude")
            let longitude = UserDefaults.standard.double(forKey: "restore_longitude")
            let status = UserDefaults.standard.integer(forKey: "restore_status")
            
            if isBroadcasting || isScanning {
                result([
                    "isBroadcasting": isBroadcasting,
                    "isScanning": isScanning,
                    "latitude": latitude,
                    "longitude": longitude,
                    "status": status
                ])
            } else {
                result(nil)
            }
            
        case "requestIgnoreBatteryOptimization":
            // iOS doesn't support this
            result(true)
            
        case "isIgnoringBatteryOptimization":
            // iOS doesn't have battery optimization like Android
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func setupBLEChannels(controller: FlutterViewController) {
        // Method channel for BLE commands
        let methodChannel = FlutterMethodChannel(
            name: "com.project_flutter/ble",
            binaryMessenger: controller.binaryMessenger
        )
        
        methodChannel.setMethodCallHandler { [weak self] (call, result) in
            self?.handleBLEMethodCall(call: call, result: result)
        }
        
        // Event channel for BLE events
        bleEventChannel = FlutterEventChannel(
            name: "com.project_flutter/ble_events",
            binaryMessenger: controller.binaryMessenger
        )
        
        bleEventChannel?.setStreamHandler(BLEEventStreamHandler())
        
        // Initialize BLE Manager
        BLEManager.shared.setup()
    }
    
    private func handleBLEMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Wrap in error handling to prevent crashes from unexpected exceptions
        do {
            try handleBLEMethodCallUnsafe(call: call, result: result)
        } catch {
            result(FlutterError(code: "NATIVE_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleBLEMethodCallUnsafe(call: FlutterMethodCall, result: @escaping FlutterResult) throws {
        switch call.method {
        case "startBroadcasting":
            guard let args = call.arguments as? [String: Any],
                  let packetBytes = args["packet"] as? [UInt8] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing packet data", details: nil))
                return
            }
            let data = Data(packetBytes)
            result(BLEManager.shared.startBroadcasting(packetData: data))

        case "stopBroadcasting":
            result(BLEManager.shared.stopBroadcasting())

        case "startScanning":
            result(BLEManager.shared.startScanning())

        case "stopScanning":
            result(BLEManager.shared.stopScanning())

        case "checkInternet":
            DispatchQueue.global().async {
                let hasInternet = BLEManager.shared.checkInternet()
                DispatchQueue.main.async {
                    result(hasInternet)
                }
            }

        case "getDeviceUuid":
            result(BLEManager.shared.getDeviceUUID())

        case "supportsBle5":
            // iPhone 8 and later support BLE 5
            result(true)

        case "requestBatteryExemption":
            // iOS doesn't support this, always return true
            result(true)

        case "checkWifiStatus":
            // Check if WiFi is enabled - iOS doesn't expose this easily without NetworkExtension
            // Return false to indicate we can't determine WiFi interference
            result(false)

        case "testNotification":
            // Test notification by simulating an SOS packet
            BLEManager.shared.testNotification()
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    override func applicationWillTerminate(_ application: UIApplication) {
        // Clean up BLE resources before app terminates
        BLEManager.shared.stopAll()
        
        // Remove observer
        if let observer = lowPowerModeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        super.applicationWillTerminate(application)
    }
}

// MARK: - Event Stream Handler

class BLEEventStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        BLEManager.shared.setEventSink(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        BLEManager.shared.setEventSink(nil)
        return nil
    }
}
