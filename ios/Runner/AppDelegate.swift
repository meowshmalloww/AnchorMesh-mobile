import Flutter
import UIKit
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate {

    private var bleEventChannel: FlutterEventChannel?
    private var isChannelsSetup = false

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
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
        isChannelsSetup = true
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
            
        case "requestBatteryExemption":
            // iOS doesn't support this, always return true
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    override func applicationWillTerminate(_ application: UIApplication) {
        // Clean up BLE resources before app terminates
        BLEManager.shared.stopAll()
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
