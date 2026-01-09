import Foundation
import CoreBluetooth
import Flutter
import UserNotifications

/// BLE Manager for iOS - Handles CoreBluetooth operations
/// Supports both Peripheral (advertising) and Central (scanning) modes
/// Also handles background SOS notifications
class BLEManager: NSObject {

    // MARK: - Constants

    /// Custom service UUID for SOS mesh
    static let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")

    /// Characteristic UUID for SOS packet data (READ)
    static let characteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABD")

    /// Characteristic UUID for relay write (WRITE) - for devices that can't advertise
    static let writeCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABE")

    /// Max relay queue size
    static let maxRelayQueueSize = 10

    /// State restoration identifier
    static let centralRestoreId = "com.development.heyblue.central"
    static let peripheralRestoreId = "com.development.heyblue.peripheral"

    /// Packet header
    private static let packetHeader: UInt16 = 0xFFFF

    /// SOS Status codes (must match sos_status.dart)
    private enum SOSStatus: UInt8 {
        case safe = 0
        case sos = 1
        case medical = 2
        case trapped = 3
        case supplies = 4

        var title: String {
            switch self {
            case .safe: return "Safe"
            case .sos: return "Emergency SOS Signal"
            case .medical: return "Medical Emergency"
            case .trapped: return "Person Trapped"
            case .supplies: return "Supplies Needed"
            }
        }
    }
    
    // MARK: - Properties
    
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?

    private var sosCharacteristic: CBMutableCharacteristic?
    private var writeCharacteristic: CBMutableCharacteristic?
    private var currentPacketData: Data?

    /// Relay queue for packets received via write (from non-advertising devices)
    private var relayQueue: [Data] = []

    /// Index for round-robin broadcasting between own packet and relay queue
    private var broadcastIndex: Int = 0
    
    private var discoveredPeripherals: [CBPeripheral] = []
    private var connectedPeripherals: [CBPeripheral] = []
    private var scannedUUIDs: Set<CBUUID> = []
    
    private var eventSink: FlutterEventSink?
    
    private var isScanning = false
    private var isBroadcasting = false

    private var lowPowerModeObserver: NSObjectProtocol?

    // Track RSSI for peripherals (by identifier UUID string)
    private var peripheralRssiMap: [String: Int] = [:]

    // Track notified packets to avoid duplicates (userId_sequence)
    private var notifiedPackets: Set<String> = []

    // Flag for background monitoring state
    private var backgroundMonitoringEnabled = false
    
    // MARK: - Singleton
    
    static let shared = BLEManager()
    
    private override init() {
        super.init()
        setupLowPowerModeObserver()
    }
    
    // MARK: - Setup
    
    func setup() {
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
    }
    
    private func setupLowPowerModeObserver() {
        lowPowerModeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sendEvent(type: "lowPowerModeChanged", data: ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
    }
    
    // MARK: - Flutter Channel Setup
    
    func setEventSink(_ sink: FlutterEventSink?) {
        self.eventSink = sink
    }
    
    private func sendEvent(type: String, data: Any?) {
        eventSink?(["type": type, "data": data as Any])
    }
    
    private func updateState(_ state: String) {
        sendEvent(type: "stateChanged", data: state)
    }
    
    // MARK: - Broadcasting (Peripheral Mode)
    
    func startBroadcasting(packetData: Data) -> Bool {
        print("BLEManager: startBroadcasting called with \(packetData.count) bytes")

        guard let peripheralManager = peripheralManager,
              peripheralManager.state == .poweredOn else {
            print("BLEManager: Bluetooth not available for broadcasting")
            sendEvent(type: "error", data: "Bluetooth not available")
            return false
        }

        print("BLEManager: Peripheral manager state is powered on, proceeding...")
        currentPacketData = packetData

        // Create read characteristic for broadcasting our SOS packet
        sosCharacteristic = CBMutableCharacteristic(
            type: BLEManager.characteristicUUID,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )

        // Create write characteristic for receiving packets from non-advertising devices
        writeCharacteristic = CBMutableCharacteristic(
            type: BLEManager.writeCharacteristicUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        // Create service with both characteristics
        let service = CBMutableService(type: BLEManager.serviceUUID, primary: true)
        service.characteristics = [sosCharacteristic!, writeCharacteristic!]
        
        peripheralManager.add(service)
        
        // Start advertising
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEManager.serviceUUID],
            CBAdvertisementDataLocalNameKey: "SOS_MESH"
        ])
        
        isBroadcasting = true
        updateCurrentState()
        print("BLEManager: Broadcasting started successfully!")

        // Keep screen on (foreground only)
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        return true
    }

    func stopBroadcasting() -> Bool {
        print("BLEManager: stopBroadcasting called")
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
        
        // Scan for our service OR saved UUIDs (for background)
        let serviceUUIDs: [CBUUID]? = UIApplication.shared.applicationState == .background
            ? Array(scannedUUIDs)
            : nil
        
        centralManager.scanForPeripherals(
            withServices: serviceUUIDs ?? [BLEManager.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        isScanning = true
        updateCurrentState()
        
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

    func checkWifiStatus() -> Bool {
        // Simple check if Wi-Fi is enabled/connected
        // In a real app, you might use Network framework for more detail
        return checkInternet() // For now, reuse internet check as proxy for connectivity
    }
    
    func isLowPowerModeEnabled() -> Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    
    func getDeviceUUID() -> String {
        // Use identifierForVendor as device UUID
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
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
            // Store RSSI for this peripheral
            peripheralRssiMap[peripheral.identifier.uuidString] = RSSI.intValue
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
    
    // State restoration - called when app is relaunched due to BLE event
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        print("BLEManager: Restoring central manager state")

        // Restore discovered peripherals
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            discoveredPeripherals = peripherals
            // Set delegate for restored peripherals
            for peripheral in peripherals {
                peripheral.delegate = self
            }
            print("BLEManager: Restored \(peripherals.count) peripherals")
        }

        // Restore scan services
        if let scanServices = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] {
            scanServices.forEach { scannedUUIDs.insert($0) }
            print("BLEManager: Restored \(scanServices.count) scan services")
        }

        // Check if background monitoring was enabled
        backgroundMonitoringEnabled = UserDefaults.standard.bool(forKey: "backgroundMonitoringEnabled")

        // Resume scanning if it was active
        if backgroundMonitoringEnabled {
            isScanning = true
            print("BLEManager: Background monitoring was enabled, will resume scanning")
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
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        // Handle service modifications - re-discover services if needed
        print("BLEManager: Services modified for peripheral \(peripheral.name ?? peripheral.identifier.uuidString)")

        // Check if our service was invalidated
        let sosServiceInvalidated = invalidatedServices.contains { $0.uuid == BLEManager.serviceUUID }
        if sosServiceInvalidated {
            // Re-discover our service
            peripheral.discoverServices([BLEManager.serviceUUID])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLEManager.characteristicUUID,
              let data = characteristic.value else { return }

        // Get RSSI for this peripheral
        let rssi = peripheralRssiMap[peripheral.identifier.uuidString] ?? -100
        peripheralRssiMap.removeValue(forKey: peripheral.identifier.uuidString)

        // Send received packet to Flutter (if app is active)
        sendEvent(type: "packetReceived", data: Array(data))

        // In background, also trigger local notification
        let appState = UIApplication.shared.applicationState
        if appState == .background || appState == .inactive {
            triggerSOSNotificationIfNeeded(packetData: data, rssi: rssi)
        }

        // Disconnect after reading
        centralManager?.cancelPeripheralConnection(peripheral)
    }
}

// MARK: - SOS Notification Handling

extension BLEManager {

    /// Parse packet data and trigger local notification if it's an emergency SOS
    private func triggerSOSNotificationIfNeeded(packetData: Data, rssi: Int) {
        // Validate packet size (minimum 17 bytes for core data, 25 for full packet)
        guard packetData.count >= 17 else {
            print("BLEManager: Packet too small: \(packetData.count) bytes")
            return
        }

        // Parse packet structure
        // Bytes 0-1: Header (0xFFFF)
        // Bytes 2-5: User ID (4 bytes)
        // Bytes 6-7: Sequence number
        // Bytes 8-11: Latitude x 10^7
        // Bytes 12-15: Longitude x 10^7
        // Byte 16: Status code

        let header = packetData.withUnsafeBytes { ptr -> UInt16 in
            ptr.load(fromByteOffset: 0, as: UInt16.self).bigEndian
        }

        guard header == BLEManager.packetHeader else {
            print("BLEManager: Invalid packet header: \(header)")
            return
        }

        let userId = packetData.withUnsafeBytes { ptr -> Int32 in
            ptr.load(fromByteOffset: 2, as: Int32.self).bigEndian
        }

        let sequence = packetData.withUnsafeBytes { ptr -> UInt16 in
            ptr.load(fromByteOffset: 6, as: UInt16.self).bigEndian
        }

        let latitudeE7 = packetData.withUnsafeBytes { ptr -> Int32 in
            ptr.load(fromByteOffset: 8, as: Int32.self).bigEndian
        }

        let longitudeE7 = packetData.withUnsafeBytes { ptr -> Int32 in
            ptr.load(fromByteOffset: 12, as: Int32.self).bigEndian
        }

        let statusByte = packetData[16]
        guard let status = SOSStatus(rawValue: statusByte) else {
            print("BLEManager: Unknown status code: \(statusByte)")
            return
        }

        // Don't notify for SAFE status
        guard status != .safe else {
            print("BLEManager: Received SAFE status from user \(userId), not notifying")
            return
        }

        // Check for duplicate (userId + sequence)
        let packetKey = "\(userId)_\(sequence)"
        guard !notifiedPackets.contains(packetKey) else {
            print("BLEManager: Already notified for packet: \(packetKey)")
            return
        }

        // Add to notified set (limit size)
        notifiedPackets.insert(packetKey)
        if notifiedPackets.count > 500 {
            // Remove some entries
            for _ in 0..<100 {
                if let first = notifiedPackets.first {
                    notifiedPackets.remove(first)
                }
            }
        }

        // Convert coordinates
        let latitude = Double(latitudeE7) / 10_000_000.0
        let longitude = Double(longitudeE7) / 10_000_000.0

        // Calculate distance from RSSI
        let distance = calculateDistanceFromRssi(rssi)

        print("BLEManager: SOS Alert - User \(userId), Status \(status), Location (\(latitude), \(longitude)), Distance: \(distance)")

        // Trigger notification
        showSOSNotification(userId: Int(userId), status: status, latitude: latitude, longitude: longitude, distance: distance)
    }

    private func calculateDistanceFromRssi(_ rssi: Int) -> String {
        // Path loss formula: d = 10^((MeasuredPower - RSSI) / (10 * N))
        let measuredPower: Double = -69.0
        let n: Double = 3.0
        let distance = pow(10.0, (measuredPower - Double(rssi)) / (10.0 * n))

        switch distance {
        case ..<2: return "Very Close (<2m)"
        case ..<5: return "Close (~\(Int(distance))m)"
        case ..<10: return "Nearby (~\(Int(distance))m)"
        case ..<50: return "Medium (~\(Int(distance))m)"
        case ..<100: return "Far (~\(Int(distance))m)"
        default: return "Very Far (>100m)"
        }
    }

    private func showSOSNotification(userId: Int, status: SOSStatus, latitude: Double, longitude: Double, distance: String) {
        let content = UNMutableNotificationContent()
        content.title = status.title
        content.body = "Distance: \(distance)\nLocation: \(String(format: "%.6f", latitude)), \(String(format: "%.6f", longitude))"
        content.sound = .default

        // Add user info for app to handle when opened
        content.userInfo = [
            "sos_user_id": userId,
            "sos_latitude": latitude,
            "sos_longitude": longitude,
            "sos_status": status.rawValue
        ]

        // Use time-sensitive interruption level for iOS 15+
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        // Create unique identifier based on userId
        let identifier = "sos_alert_\(userId)_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("BLEManager: Error showing notification: \(error)")
            } else {
                print("BLEManager: SOS notification shown for user \(userId)")
            }
        }
    }

    /// Request notification permission
    func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("BLEManager: Notification authorization error: \(error)")
                }
                completion(granted)
            }
        }
    }

    /// Check if notification permission is granted
    func hasNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }

    /// Enable background monitoring
    func enableBackgroundMonitoring() -> Bool {
        backgroundMonitoringEnabled = true
        UserDefaults.standard.set(true, forKey: "backgroundMonitoringEnabled")

        // Ensure scanning is active
        if !isScanning, let centralManager = centralManager, centralManager.state == .poweredOn {
            _ = startScanning()
        }

        return true
    }

    /// Disable background monitoring
    func disableBackgroundMonitoring() -> Bool {
        backgroundMonitoringEnabled = false
        UserDefaults.standard.set(false, forKey: "backgroundMonitoringEnabled")
        return true
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEManager: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        // State handled by centralManagerDidUpdateState
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == BLEManager.characteristicUUID else {
            peripheral.respond(to: request, withResult: .invalidHandle)
            return
        }

        // Get next packet to broadcast (round-robin between own and relay queue)
        guard let data = getNextBroadcastPacket() else {
            peripheral.respond(to: request, withResult: .invalidHandle)
            return
        }

        request.value = data
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == BLEManager.writeCharacteristicUUID,
               let data = request.value {
                // Process received packet for relay
                onRelayPacketReceived(packetData: data)
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .invalidHandle)
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        // Handle state restoration
    }

    // MARK: - Relay Queue Management

    /// Get next packet to broadcast - alternates between own packet and relay queue
    private func getNextBroadcastPacket() -> Data? {
        broadcastIndex += 1

        // Priority: own packet gets 50% of broadcasts, relay queue gets 50%
        if broadcastIndex % 2 == 0, let ownPacket = currentPacketData {
            return ownPacket
        }

        if !relayQueue.isEmpty {
            let index = (broadcastIndex / 2) % relayQueue.count
            return relayQueue[index]
        }

        return currentPacketData
    }

    /// Handle packet received via write from non-advertising device
    private func onRelayPacketReceived(packetData: Data) {
        // Validate packet (minimum size check)
        guard packetData.count >= 17 else {
            print("BLEManager: Relay packet too small: \(packetData.count) bytes")
            return
        }

        // Check if we already have this packet (by comparing first 8 bytes - userId + sequence)
        let packetPrefix = packetData.prefix(8)
        let exists = relayQueue.contains { $0.prefix(8) == packetPrefix }

        if !exists {
            // Add to relay queue
            relayQueue.append(packetData)

            // Enforce max queue size (FIFO)
            while relayQueue.count > BLEManager.maxRelayQueueSize {
                relayQueue.removeFirst()
            }

            print("BLEManager: Received relay packet, queue size: \(relayQueue.count)")

            // Send to Flutter for UI display
            sendEvent(type: "packetReceived", data: Array(packetData))

            // Trigger notification if in background
            let appState = UIApplication.shared.applicationState
            if appState == .background || appState == .inactive {
                triggerSOSNotificationIfNeeded(packetData: packetData, rssi: -50) // Default RSSI for local write
            }
        } else {
            print("BLEManager: Duplicate relay packet ignored")
        }
    }
}
