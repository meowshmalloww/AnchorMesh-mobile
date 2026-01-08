import Foundation
import Flutter
import CoreBluetooth

/// BLE Peripheral Handler for iOS
/// Implements advertising and GATT server for SOS mesh networking
class BLEPeripheralHandler: NSObject, FlutterPlugin, FlutterStreamHandler {

    // MARK: - Properties

    private var peripheralManager: CBPeripheralManager?
    private var eventSink: FlutterEventSink?
    private var methodChannel: FlutterMethodChannel?

    // Service and Characteristic UUIDs
    private let sosServiceUUID = CBUUID(string: "00005050-0000-1000-8000-00805f9b34fb")
    private let sosAlertCharUUID = CBUUID(string: "00005051-0000-1000-8000-00805f9b34fb")
    private let deviceInfoCharUUID = CBUUID(string: "00005052-0000-1000-8000-00805f9b34fb")
    private let ackCharUUID = CBUUID(string: "00005053-0000-1000-8000-00805f9b34fb")

    // GATT Service and Characteristics
    private var sosService: CBMutableService?
    private var sosAlertCharacteristic: CBMutableCharacteristic?
    private var deviceInfoCharacteristic: CBMutableCharacteristic?
    private var ackCharacteristic: CBMutableCharacteristic?

    // State
    private var isAdvertising = false
    private var currentAdvertisementData: [UInt8]?
    private var localName: String = "SOS-Device"
    private var connectedCentrals: [CBCentral] = []

    // MARK: - Plugin Registration

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BLEPeripheralHandler()

        // Method channel for commands
        let methodChannel = FlutterMethodChannel(
            name: "com.sosapp/ble_peripheral",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        instance.methodChannel = methodChannel

        // Event channel for async events
        let eventChannel = FlutterEventChannel(
            name: "com.sosapp/ble_peripheral_events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - FlutterPlugin

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initialize(result: result)

        case "startAdvertising":
            guard let args = call.arguments as? [String: Any],
                  let data = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing data", details: nil))
                return
            }
            let serviceUuid = args["serviceUuid"] as? String
            let name = args["localName"] as? String ?? "SOS-Device"
            startAdvertising(data: [UInt8](data.data), serviceUuid: serviceUuid, localName: name, result: result)

        case "updateAdvertisement":
            guard let args = call.arguments as? [String: Any],
                  let data = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing data", details: nil))
                return
            }
            updateAdvertisement(data: [UInt8](data.data), result: result)

        case "stopAdvertising":
            stopAdvertising(result: result)

        case "sendData":
            guard let args = call.arguments as? [String: Any],
                  let deviceAddress = args["deviceAddress"] as? String,
                  let data = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing parameters", details: nil))
                return
            }
            sendData(to: deviceAddress, data: [UInt8](data.data), result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - BLE Methods

    private func initialize(result: @escaping FlutterResult) {
        // Create peripheral manager
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)

        // Return supported status (will be updated when state changes)
        result([
            "supported": true,
            "state": peripheralManager?.state.rawValue ?? -1
        ])
    }

    private func setupGATTServer() {
        guard let manager = peripheralManager, manager.state == .poweredOn else { return }

        // Create characteristics
        sosAlertCharacteristic = CBMutableCharacteristic(
            type: sosAlertCharUUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )

        deviceInfoCharacteristic = CBMutableCharacteristic(
            type: deviceInfoCharUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        ackCharacteristic = CBMutableCharacteristic(
            type: ackCharUUID,
            properties: [.write, .notify],
            value: nil,
            permissions: [.writeable]
        )

        // Create service
        sosService = CBMutableService(type: sosServiceUUID, primary: true)
        sosService?.characteristics = [
            sosAlertCharacteristic!,
            deviceInfoCharacteristic!,
            ackCharacteristic!
        ]

        // Add service to peripheral manager
        manager.add(sosService!)
    }

    private func startAdvertising(data: [UInt8], serviceUuid: String?, localName: String, result: @escaping FlutterResult) {
        guard let manager = peripheralManager, manager.state == .poweredOn else {
            result(FlutterError(code: "NOT_READY", message: "Bluetooth not ready", details: nil))
            return
        }

        // Stop any existing advertising
        if isAdvertising {
            manager.stopAdvertising()
        }

        currentAdvertisementData = data
        self.localName = localName

        // Update the SOS alert characteristic with the data
        if let char = sosAlertCharacteristic {
            char.value = Data(data)
            manager.updateValue(Data(data), for: char, onSubscribedCentrals: nil)
        }

        // Build advertisement data
        var advertisementData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: localName,
            CBAdvertisementDataServiceUUIDsKey: [sosServiceUUID]
        ]

        // Start advertising
        manager.startAdvertising(advertisementData)
        isAdvertising = true

        result(true)
    }

    private func updateAdvertisement(data: [UInt8], result: @escaping FlutterResult) {
        guard let manager = peripheralManager, manager.state == .poweredOn else {
            result(FlutterError(code: "NOT_READY", message: "Bluetooth not ready", details: nil))
            return
        }

        currentAdvertisementData = data

        // Update the characteristic value
        if let char = sosAlertCharacteristic {
            char.value = Data(data)
            manager.updateValue(Data(data), for: char, onSubscribedCentrals: nil)
        }

        result(true)
    }

    private func stopAdvertising(result: @escaping FlutterResult) {
        peripheralManager?.stopAdvertising()
        isAdvertising = false
        currentAdvertisementData = nil

        sendEvent(["type": "advertisingStopped"])
        result(nil)
    }

    private func sendData(to deviceAddress: String, data: [UInt8], result: @escaping FlutterResult) {
        guard let manager = peripheralManager,
              let char = sosAlertCharacteristic else {
            result(false)
            return
        }

        // Find the central by address
        if let central = connectedCentrals.first(where: { $0.identifier.uuidString == deviceAddress }) {
            let success = manager.updateValue(Data(data), for: char, onSubscribedCentrals: [central])
            result(success)
        } else {
            // Broadcast to all connected centrals
            let success = manager.updateValue(Data(data), for: char, onSubscribedCentrals: nil)
            result(success)
        }
    }

    // MARK: - Helper Methods

    private func sendEvent(_ event: [String: Any]) {
        DispatchQueue.main.async {
            self.eventSink?(event)
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheralHandler: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            setupGATTServer()
            sendEvent([
                "type": "stateChanged",
                "state": "poweredOn"
            ])

        case .poweredOff:
            isAdvertising = false
            sendEvent([
                "type": "stateChanged",
                "state": "poweredOff"
            ])

        case .unauthorized:
            sendEvent([
                "type": "advertisingError",
                "message": "Bluetooth permission denied"
            ])

        case .unsupported:
            sendEvent([
                "type": "advertisingError",
                "message": "BLE peripheral mode not supported"
            ])

        default:
            break
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            isAdvertising = false
            sendEvent([
                "type": "advertisingError",
                "message": error.localizedDescription
            ])
        } else {
            isAdvertising = true
            sendEvent(["type": "advertisingStarted"])
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            sendEvent([
                "type": "serviceError",
                "message": error.localizedDescription
            ])
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if !connectedCentrals.contains(where: { $0.identifier == central.identifier }) {
            connectedCentrals.append(central)
        }

        sendEvent([
            "type": "peerConnected",
            "deviceAddress": central.identifier.uuidString
        ])

        // Send current SOS data to the newly subscribed central
        if let data = currentAdvertisementData, let char = sosAlertCharacteristic {
            peripheral.updateValue(Data(data), for: char, onSubscribedCentrals: [central])
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        connectedCentrals.removeAll { $0.identifier == central.identifier }

        sendEvent([
            "type": "peerDisconnected",
            "deviceAddress": central.identifier.uuidString
        ])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == sosAlertCharUUID ||
               request.characteristic.uuid == ackCharUUID {

                if let data = request.value {
                    sendEvent([
                        "type": "dataReceived",
                        "deviceAddress": request.central.identifier.uuidString,
                        "characteristicUuid": request.characteristic.uuid.uuidString,
                        "data": [UInt8](data)
                    ])

                    // Check if this is an SOS beacon
                    if request.characteristic.uuid == sosAlertCharUUID && data.count >= 22 {
                        sendEvent([
                            "type": "beaconReceived",
                            "deviceAddress": request.central.identifier.uuidString,
                            "data": [UInt8](data),
                            "rssi": -50  // We don't have RSSI for write requests
                        ])
                    }
                }

                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == sosAlertCharUUID {
            if let data = currentAdvertisementData {
                request.value = Data(data)
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .attributeNotFound)
            }
        } else if request.characteristic.uuid == deviceInfoCharUUID {
            // Return device info
            let deviceInfo = [
                "platform": "ios",
                "version": UIDevice.current.systemVersion
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: deviceInfo) {
                request.value = jsonData
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .unlikelyError)
            }
        } else {
            peripheral.respond(to: request, withResult: .requestNotSupported)
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // The peripheral is ready to send more updates
        // Re-send current data if we have it
        if let data = currentAdvertisementData, let char = sosAlertCharacteristic {
            peripheral.updateValue(Data(data), for: char, onSubscribedCentrals: nil)
        }
    }
}
