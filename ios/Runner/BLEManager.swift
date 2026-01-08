import Foundation
import CoreBluetooth
import Flutter

/// BLE Manager for iOS - Handles CoreBluetooth operations
/// Supports both Peripheral (advertising) and Central (scanning) modes
class BLEManager: NSObject {
    
    // MARK: - Constants
    
    /// Custom service UUID for SOS mesh
    static let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
    
    /// Characteristic UUID for SOS packet data
    static let characteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABD")
    
    /// State restoration identifier
    static let centralRestoreId = "com.project_flutter.central"
    static let peripheralRestoreId = "com.project_flutter.peripheral"
    
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
            discoveredPeripherals = peripherals
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
