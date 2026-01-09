import Foundation
import CoreBluetooth
import Flutter
import UserNotifications
import AudioToolbox

/// BLE Manager for iOS - Handles CoreBluetooth operations
/// Supports both Peripheral (advertising) and Central (scanning) modes
class BLEManager: NSObject {
    
    // MARK: - Constants

    /// Custom service UUID for SOS mesh
    static let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")

    /// Characteristic UUID for SOS packet data
    static let characteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABD")

    /// State restoration identifier
    static let centralRestoreId = "com.development.heyblue.central"
    static let peripheralRestoreId = "com.development.heyblue.peripheral"

    /// Status codes from SOS packet (byte 16)
    static let STATUS_SAFE: UInt8 = 0x00
    static let STATUS_SOS: UInt8 = 0x01
    static let STATUS_MEDICAL: UInt8 = 0x02
    static let STATUS_TRAPPED: UInt8 = 0x03
    static let STATUS_SUPPLIES: UInt8 = 0x04
    
    // MARK: - Properties
    
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    
    private var sosCharacteristic: CBMutableCharacteristic?
    private var currentPacketData: Data?
    
    private var discoveredPeripherals: [CBPeripheral] = []
    private var connectedPeripherals: [CBPeripheral] = []
    private var scannedUUIDs: Set<CBUUID> = []
    
    private var eventSink: FlutterEventSink?
    
    private var isScanning = false
    private var isBroadcasting = false

    private var lowPowerModeObserver: NSObjectProtocol?
    private var isSetup = false
    private var lifecycleObserversSetup = false
    
    // MARK: - Singleton
    
    static let shared = BLEManager()
    
    private override init() {
        super.init()
        setupLowPowerModeObserver()
        setupAppLifecycleObserver()
    }

    private func setupAppLifecycleObserver() {
        // Prevent duplicate observers
        guard !lifecycleObserversSetup else { return }
        lifecycleObserversSetup = true

        // Listen for app entering background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // Listen for app becoming active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        print("App entered background - BLE operations continue")
        // BLE operations continue automatically with state restoration
        // No need to restart - CoreBluetooth handles background mode
    }

    @objc private func appWillEnterForeground() {
        print("App entering foreground")
        // Restart scanning if it was active
        if isScanning {
            centralManager?.stopScan()
            _ = startScanning()
        }
    }
    
    // MARK: - Setup

    func setup() {
        // Prevent double initialization
        guard !isSetup else {
            print("BLEManager already setup, skipping")
            return
        }
        isSetup = true

        // Initialize managers with state restoration
        centralManager = CBCentralManager(
            delegate: self,
            queue: DispatchQueue.main,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: BLEManager.centralRestoreId,
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )

        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: DispatchQueue.main,
            options: [
                CBPeripheralManagerOptionRestoreIdentifierKey: BLEManager.peripheralRestoreId
            ]
        )

        // Request notification permission for SOS alerts
        requestNotificationPermission()
    }

    /// Reset manager state for new Flutter engine connection (app relaunch)
    func reset() {
        print("BLEManager reset for new app session")

        // Clear stale event sink
        eventSink = nil

        // Reset setup flag to allow re-initialization
        isSetup = false

        // Clear stale peripheral references
        discoveredPeripherals.removeAll()
        connectedPeripherals.removeAll()
        scannedUUIDs.removeAll()

        // Reset BLE operation flags
        isScanning = false
        isBroadcasting = false
    }
    
    private func setupLowPowerModeObserver() {
        // Prevent duplicate observers
        guard lowPowerModeObserver == nil else { return }

        lowPowerModeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sendEvent(type: "lowPowerModeChanged", data: ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
    }

    // MARK: - Notification Setup

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    private func showSOSNotification(packetData: Data) {
        // Parse packet to extract status (byte 16) and location
        guard packetData.count >= 21 else {
            print("Packet too small for notification: \(packetData.count)")
            return
        }

        let status = packetData[16]

        // Don't notify for SAFE status
        if status == BLEManager.STATUS_SAFE {
            print("Received SAFE status, no notification needed")
            return
        }

        // Extract lat/lon (bytes 8-15, stored as int * 10^7, little endian)
        let latE7 = Int32(bitPattern:
            UInt32(packetData[8]) |
            (UInt32(packetData[9]) << 8) |
            (UInt32(packetData[10]) << 16) |
            (UInt32(packetData[11]) << 24)
        )
        let lonE7 = Int32(bitPattern:
            UInt32(packetData[12]) |
            (UInt32(packetData[13]) << 8) |
            (UInt32(packetData[14]) << 16) |
            (UInt32(packetData[15]) << 24)
        )

        let lat = Double(latE7) / 10000000.0
        let lon = Double(lonE7) / 10000000.0

        // Get status text and emoji
        let (title, emoji): (String, String)
        switch status {
        case BLEManager.STATUS_SOS:
            (title, emoji) = ("EMERGENCY SOS", "🆘")
        case BLEManager.STATUS_MEDICAL:
            (title, emoji) = ("MEDICAL EMERGENCY", "🏥")
        case BLEManager.STATUS_TRAPPED:
            (title, emoji) = ("PERSON TRAPPED", "🚨")
        case BLEManager.STATUS_SUPPLIES:
            (title, emoji) = ("SUPPLIES NEEDED", "📦")
        default:
            (title, emoji) = ("EMERGENCY ALERT", "⚠️")
        }

        let notificationTitle = "\(emoji) \(title)"
        let notificationBody = String(format: "Someone nearby needs help! Location: %.4f, %.4f", lat, lon)

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = notificationTitle
        content.body = notificationBody
        content.sound = UNNotificationSound.default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        content.categoryIdentifier = "SOS_ALERT"

        // Create trigger (immediate)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        // Create request with unique identifier
        let request = UNNotificationRequest(
            identifier: "sos_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        // Add notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to show notification: \(error)")
            } else {
                print("SOS notification shown: \(title)")
            }
        }

        // Also vibrate and play system sound for extra alertness
        vibrateDevice()
    }

    private func vibrateDevice() {
        // Play alert sound
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))

        // Heavy haptic feedback
        if #available(iOS 10.0, *) {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)

            // Multiple vibrations for emergency
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                generator.notificationOccurred(.error)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                generator.notificationOccurred(.error)
            }
        }
    }
    
    // MARK: - Flutter Channel Setup
    
    func setEventSink(_ sink: FlutterEventSink?) {
        self.eventSink = sink
    }
    
    private func sendEvent(type: String, data: Any?) {
        // Safety: Check if sink is still valid before sending
        guard let sink = eventSink else { return }

        // Dispatch on main thread to avoid threading issues
        DispatchQueue.main.async {
            sink(["type": type, "data": data as Any])
        }
    }
    
    private func updateState(_ state: String) {
        sendEvent(type: "stateChanged", data: state)
    }
    
    // MARK: - Broadcasting (Peripheral Mode)
    
    func startBroadcasting(packetData: Data) -> Bool {
        guard let peripheralManager = peripheralManager,
              peripheralManager.state == .poweredOn else {
            sendEvent(type: "error", data: "Bluetooth not available")
            return false
        }
        
        currentPacketData = packetData
        
        // Create characteristic with SOS data
        sosCharacteristic = CBMutableCharacteristic(
            type: BLEManager.characteristicUUID,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        
        // Create service
        let service = CBMutableService(type: BLEManager.serviceUUID, primary: true)
        service.characteristics = [sosCharacteristic!]
        
        peripheralManager.add(service)
        
        // Start advertising
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEManager.serviceUUID],
            CBAdvertisementDataLocalNameKey: "SOS_MESH"
        ])
        
        isBroadcasting = true
        updateCurrentState()
        
        // Keep screen on (foreground only)
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        
        return true
    }
    
    func stopBroadcasting() -> Bool {
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        
        isBroadcasting = false
        updateCurrentState()
        
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        
        return true
    }
    
    // MARK: - Scanning (Central Mode)
    
    func startScanning() -> Bool {
        guard let centralManager = centralManager,
              centralManager.state == .poweredOn else {
            sendEvent(type: "error", data: "Bluetooth not available")
            return false
        }

        // Always scan for our SOS service UUID - this works in background mode too
        // iOS requires specific service UUIDs for background scanning (no wildcard)
        centralManager.scanForPeripherals(
            withServices: [BLEManager.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        isScanning = true
        updateCurrentState()

        print("BLE scanning started for SOS service")
        return true
    }
    
    func stopScanning() -> Bool {
        centralManager?.stopScan()
        isScanning = false
        updateCurrentState()
        return true
    }
    
    private func updateCurrentState() {
        let state: String
        if isBroadcasting && isScanning {
            state = "meshActive"
        } else if isBroadcasting {
            state = "broadcasting"
        } else if isScanning {
            state = "scanning"
        } else {
            state = "idle"
        }
        updateState(state)
    }
    
    // MARK: - Utility
    
    func checkInternet() -> Bool {
        // Simple reachability check
        guard let url = URL(string: "https://www.google.com") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        let semaphore = DispatchSemaphore(value: 0)
        var hasInternet = false
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                hasInternet = httpResponse.statusCode == 200
            }
            semaphore.signal()
        }.resume()
        
        semaphore.wait()
        return hasInternet
    }
    
    func isLowPowerModeEnabled() -> Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    
    func getDeviceUUID() -> String {
        // Use identifierForVendor as device UUID
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }

    // MARK: - Testing

    /// Test notification by simulating an SOS packet reception
    func testNotification() {
        // Create a fake SOS packet (25 bytes)
        var testPacket = Data(count: 25)

        // Header: 0xFFFF
        testPacket[0] = 0xFF
        testPacket[1] = 0xFF

        // User ID: 0x12345678
        testPacket[2] = 0x78
        testPacket[3] = 0x56
        testPacket[4] = 0x34
        testPacket[5] = 0x12

        // Sequence: 1
        testPacket[6] = 0x01
        testPacket[7] = 0x00

        // Latitude: 37.7749 * 10^7 = 377749000 (San Francisco)
        let lat: Int32 = 377749000
        testPacket[8] = UInt8(lat & 0xFF)
        testPacket[9] = UInt8((lat >> 8) & 0xFF)
        testPacket[10] = UInt8((lat >> 16) & 0xFF)
        testPacket[11] = UInt8((lat >> 24) & 0xFF)

        // Longitude: -122.4194 * 10^7 = -1224194000
        let lon: Int32 = -1224194000
        testPacket[12] = UInt8(truncatingIfNeeded: lon & 0xFF)
        testPacket[13] = UInt8(truncatingIfNeeded: (lon >> 8) & 0xFF)
        testPacket[14] = UInt8(truncatingIfNeeded: (lon >> 16) & 0xFF)
        testPacket[15] = UInt8(truncatingIfNeeded: (lon >> 24) & 0xFF)

        // Status: SOS (0x01)
        testPacket[16] = BLEManager.STATUS_SOS

        // Timestamp: current time
        let timestamp = Int32(Date().timeIntervalSince1970)
        testPacket[17] = UInt8(timestamp & 0xFF)
        testPacket[18] = UInt8((timestamp >> 8) & 0xFF)
        testPacket[19] = UInt8((timestamp >> 16) & 0xFF)
        testPacket[20] = UInt8((timestamp >> 24) & 0xFF)

        // Target ID: 0 (broadcast)
        testPacket[21] = 0x00
        testPacket[22] = 0x00
        testPacket[23] = 0x00
        testPacket[24] = 0x00

        print("Testing notification with simulated SOS packet")
        showSOSNotification(packetData: testPacket)
    }

    // MARK: - Cleanup
    
    func stopAll() {
        stopScanning()
        stopBroadcasting()
        
        for peripheral in connectedPeripherals {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripherals.removeAll()
        discoveredPeripherals.removeAll()
    }
    
    deinit {
        if let observer = lowPowerModeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            updateState("idle")
        case .poweredOff:
            updateState("bluetoothOff")
        case .unauthorized, .unsupported:
            updateState("unavailable")
        default:
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        
        // Save UUID for background scanning
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            serviceUUIDs.forEach { scannedUUIDs.insert($0) }
        }
        
        // Connect to read SOS data
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripherals.append(peripheral)
        peripheral.delegate = self
        peripheral.discoverServices([BLEManager.serviceUUID])
        
        sendEvent(type: "connectedDevicesChanged", data: connectedPeripherals.count)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripherals.removeAll { $0.identifier == peripheral.identifier }
        sendEvent(type: "connectedDevicesChanged", data: connectedPeripherals.count)
    }
    
    // State restoration
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            // Only restore peripherals that are in valid state (not disconnected)
            discoveredPeripherals = peripherals.filter { $0.state != .disconnected }

            // Re-set delegate for restored peripherals
            for peripheral in discoveredPeripherals {
                peripheral.delegate = self
            }

            print("BLE state restored with \(discoveredPeripherals.count) valid peripherals")
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services where service.uuid == BLEManager.serviceUUID {
            peripheral.discoverCharacteristics([BLEManager.characteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics where characteristic.uuid == BLEManager.characteristicUUID {
            peripheral.readValue(for: characteristic)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLEManager.characteristicUUID,
              let data = characteristic.value else { return }

        // Send received packet to Flutter
        sendEvent(type: "packetReceived", data: Array(data))

        // Show native notification for SOS alert
        showSOSNotification(packetData: data)

        // Disconnect after reading
        centralManager?.cancelPeripheralConnection(peripheral)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEManager: CBPeripheralManagerDelegate {
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        // State handled by centralManagerDidUpdateState
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == BLEManager.characteristicUUID,
              let data = currentPacketData else {
            peripheral.respond(to: request, withResult: .invalidHandle)
            return
        }
        
        request.value = data
        peripheral.respond(to: request, withResult: .success)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        // Handle state restoration
    }
}
