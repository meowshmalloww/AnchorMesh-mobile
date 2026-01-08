/// BLE Mesh Service
/// Handles Bluetooth Low Energy mesh networking for SOS relay

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/sos_alert.dart';
import '../../models/peer_device.dart';
import '../../models/device_info.dart';
import '../crypto/encryption_service.dart';
import 'ble_peripheral_service.dart';
import '../storage/database_service.dart';

/// BLE Service UUIDs for SOS Mesh
class BleUuids {
  static const String serviceUuid = '0000sos0-0000-1000-8000-00805f9b34fb';
  static const String sosAlertUuid = '0000sos1-0000-1000-8000-00805f9b34fb';
  static const String deviceInfoUuid = '0000sos2-0000-1000-8000-00805f9b34fb';
  static const String ackUuid = '0000sos3-0000-1000-8000-00805f9b34fb';
}

/// BLE Mesh configuration
class BleMeshConfig {
  final Duration scanDuration;
  final Duration scanInterval;
  final Duration advertisingInterval;
  final int maxRelayHops;
  final bool useExtendedAdvertising;

  const BleMeshConfig({
    this.scanDuration = const Duration(seconds: 10),
    this.scanInterval = const Duration(seconds: 30),
    this.advertisingInterval = const Duration(milliseconds: 100),
    this.maxRelayHops = 10,
    this.useExtendedAdvertising = false,
  });
}

/// BLE Mesh events
abstract class BleMeshEvent {}

class PeerDiscoveredEvent extends BleMeshEvent {
  final PeerDevice peer;
  PeerDiscoveredEvent(this.peer);
}

class MessageReceivedEvent extends BleMeshEvent {
  final SOSAlert message;
  final PeerDevice fromPeer;
  MessageReceivedEvent(this.message, this.fromPeer);
}

class MessageRelayedEvent extends BleMeshEvent {
  final String messageId;
  final String toPeerId;
  MessageRelayedEvent(this.messageId, this.toPeerId);
}

class AcknowledgmentReceivedEvent extends BleMeshEvent {
  final String originalMessageId;
  final bool deliveredToServer;
  AcknowledgmentReceivedEvent(this.originalMessageId, this.deliveredToServer);
}

class BleErrorEvent extends BleMeshEvent {
  final String message;
  final dynamic error;
  BleErrorEvent(this.message, [this.error]);
}

/// BLE Mesh Service for peer-to-peer SOS relay
class BLEMeshService extends ChangeNotifier {
  final BleMeshConfig config;
  final EncryptionService? encryptionService;
  final LocalDevice? localDevice;

  // State
  bool _isInitialized = false;
  bool _isScanning = false;
  bool _isAdvertising = false;

  // Peers
  final Map<String, PeerDevice> _peers = {};
  final Set<String> _connectedPeerIds = {};

  // Message tracking
  final Set<String> _processedMessageIds = {};
  final Map<String, SOSAlert> _activeAlerts = {};

  // Subscriptions
  StreamSubscription? _scanSubscription;
  StreamSubscription? _adapterStateSubscription;
  StreamSubscription? _peripheralEventSubscription;
  Timer? _scanTimer;
  Timer? _broadcastTimer;

  // Native BLE peripheral service for advertising
  final BLEPeripheralService _peripheralService = BLEPeripheralService();
  final DatabaseService _databaseService = DatabaseService();

  // Events
  final _eventController = StreamController<BleMeshEvent>.broadcast();

  BLEMeshService({
    this.config = const BleMeshConfig(),
    this.encryptionService,
    this.localDevice,
  });

  /// Event stream
  Stream<BleMeshEvent> get events => _eventController.stream;

  /// Whether service is initialized
  bool get isInitialized => _isInitialized;

  /// Whether currently scanning
  bool get isScanning => _isScanning;

  /// Whether currently advertising
  bool get isAdvertising => _isAdvertising;

  /// All discovered peers
  List<PeerDevice> get allPeers => _peers.values.toList();

  /// Connected peers
  List<PeerDevice> get connectedPeers =>
      _peers.values.where((p) => _connectedPeerIds.contains(p.deviceId)).toList();

  /// Peers with internet connectivity
  List<PeerDevice> get peersWithInternet =>
      _peers.values.where((p) => p.hasInternet).toList();

  /// Initialize the BLE service
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    // Check Bluetooth support
    if (!await FlutterBluePlus.isSupported) {
      _eventController.add(BleErrorEvent('Bluetooth not supported'));
      return false;
    }

    // Request permissions
    if (!await _requestPermissions()) {
      _eventController.add(BleErrorEvent('Bluetooth permissions denied'));
      return false;
    }

    // Initialize native peripheral service for advertising
    await _peripheralService.initialize();
    _setupPeripheralEventListener();

    // Listen to adapter state
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        _stopScanning();
        _eventController.add(BleErrorEvent('Bluetooth turned off'));
      } else if (state == BluetoothAdapterState.on && _isInitialized) {
        _startScanningLoop();
      }
    });

    // Turn on Bluetooth if needed
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        // User may need to enable manually
      }
    }

    _isInitialized = true;
    _startScanningLoop();
    notifyListeners();

    return true;
  }

  /// Setup listener for peripheral service events
  void _setupPeripheralEventListener() {
    _peripheralEventSubscription = _peripheralService.events.listen((event) {
      if (event is BeaconReceivedEvent) {
        _handleReceivedBeacon(event);
      } else if (event is DataReceivedEvent) {
        _processReceivedSosData(event.data, event.deviceAddress);
      } else if (event is PeerConnectedEvent) {
        // Update peer connection state
        final peer = _peers.values.firstWhere(
          (p) => p.bleAddress == event.deviceAddress,
          orElse: () => PeerDevice(
            deviceId: event.deviceAddress,
            bleAddress: event.deviceAddress,
          ),
        );
        if (!_peers.containsKey(peer.deviceId)) {
          _peers[peer.deviceId] = peer;
        }
        _connectedPeerIds.add(peer.deviceId);
        peer.connectionState = PeerConnectionState.connected;
        notifyListeners();
      } else if (event is AdvertisingErrorEvent) {
        _eventController.add(BleErrorEvent('Advertising error: ${event.message}'));
      }
    });
  }

  /// Handle received SOS beacon from native advertising
  Future<void> _handleReceivedBeacon(BeaconReceivedEvent event) async {
    final beacon = event.beacon;
    
    // Construct message ID from UserID + Sequence (Simple for prototype)
    final messageId = '${beacon.userId}_${beacon.sequence}';

    // Persist to DB
    final isNew = await _databaseService.saveMessage(
      messageId, 
      beacon.toBytes(), 
      0 // Unknown hop count in strict beacon, assume 0 or derived
    );

    if (!isNew) return; // Deduplication

    // Create a peer for the sender
    final peer = PeerDevice(
      deviceId: beacon.userId.toString(),
      bleAddress: event.deviceAddress,
      rssi: event.rssi,
      hasInternet: false, // Unknown in strict beacon
    );

    if (!_peers.containsKey(peer.deviceId)) {
      _peers[peer.deviceId] = peer;
      _eventController.add(PeerDiscoveredEvent(peer));
    }

    // Convert beacon to SOS alert for processing
    final emergencyIndex = beacon.status.clamp(0, EmergencyType.values.length - 1);
    final alert = SOSAlert(
      messageId: messageId,
      originatorDeviceId: beacon.userId.toString(),
      appSignature: '',
      emergencyType: EmergencyType.values[emergencyIndex],
      location: GeoLocation(
        latitude: beacon.latitude,
        longitude: beacon.longitude,
        timestamp: DateTime.fromMillisecondsSinceEpoch(beacon.timestamp * 1000),
      ),
      hopCount: beacon.sequence,
    );

    peer.recordMessage(received: true);
    _eventController.add(MessageReceivedEvent(alert, peer));
    notifyListeners();
  }

  /// Request Bluetooth permissions
  Future<bool> _requestPermissions() async {
    final permissions = [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
    ];

    for (final permission in permissions) {
      final status = await permission.request();
      if (!status.isGranted && !status.isLimited) {
        return false;
      }
    }

    return true;
  }

  /// Start the scanning loop
  void _startScanningLoop() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(config.scanInterval, (_) {
      _performScan();
    });
    _performScan(); // Initial scan
  }

  /// Perform a BLE scan
  Future<void> _performScan() async {
    if (_isScanning) return;

    _isScanning = true;
    notifyListeners();

    try {
      // Start scanning
      // Note: allowDuplicates is needed for iOS background scanning effectively 
      // but consumes more battery. Logic handles throttling.
      await FlutterBluePlus.startScan(
        timeout: config.scanDuration,
        // withServices: [Guid(BleUuids.serviceUuid)], // Scan all for now to catch 0xFFFF manufacturer data
        // allowDuplicates: true, // Removed in newer versions
        continuousUpdates: true, // Attempt to use continuousUpdates if available, or just rely on defaults
      );

      // Listen to scan results
      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          _processScanResult(result);
        }
      });

      // Wait for scan to complete
      await Future.delayed(config.scanDuration);
      await FlutterBluePlus.stopScan();
    } catch (e) {
      _eventController.add(BleErrorEvent('Scan failed', e));
    }

    _isScanning = false;
    notifyListeners();
  }

  /// Process a scan result
  void _processScanResult(ScanResult result) {
    // Check for our specific Manufacturer Data (0xFFFF)
    // Note: 0xFFFF is the decimal 65535
    final manufacturerData = result.advertisementData.manufacturerData;
    
    // Check for our App Header in the data
    // Usually the key in the map IS the manufacturer ID.
    // If we use 0xFFFF as the ID:
    if (manufacturerData.containsKey(0xFFFF)) {
       final data = manufacturerData[0xFFFF];
       if (data != null) {
         // Prepend header to match strict parsing expectations if needed
         // SOSBeacon.fromBytes expects the full packet including header
         // The map key is the header/company ID.
         // So we reconstruct: [0xFF, 0xFF, ...data]
         final fullBytes = [0xFF, 0xFF, ...data];
         final beacon = SOSBeacon.fromBytes(fullBytes);
         if (beacon != null) {
            _handleReceivedBeacon(BeaconReceivedEvent(beacon, result.rssi, result.device.remoteId.str));
         }
       }
    }
  }

  /// Extract device ID from advertisement
  String? _extractDeviceId(ScanResult result) {
    // Look for device ID in manufacturer data or service data
    final manufacturerData = result.advertisementData.manufacturerData;
    if (manufacturerData.isNotEmpty) {
      // Parse manufacturer data for device ID
      final data = manufacturerData.values.first;
      if (data.length >= 8) {
        return String.fromCharCodes(data.take(8));
      }
    }

    // Fallback to BLE address
    return result.device.remoteId.str.replaceAll(':', '');
  }

  /// Extract internet availability from advertisement
  bool _extractHasInternet(ScanResult result) {
    // Not available in strict beacon
    return false;
  }

  /// Check for SOS alerts in advertisement data
  void _checkForSosInAdvertisement(ScanResult result) {
    // Deprecated logic, moved to _processScanResult
  }

  /// Process received SOS data
  void _processReceivedSosData(List<int> data, String fromAddress) {
    // Deprecated logic, we use Beacon structure now
  }

  /// Broadcast an SOS alert
  Future<void> broadcastSOS(SOSAlert alert) async {
    _activeAlerts[alert.messageId] = alert;
    _processedMessageIds.add(alert.messageId);

    // Start continuous broadcasting
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(
      config.advertisingInterval,
      (_) => _broadcastAlert(alert),
    );
  }

  /// Broadcast alert in advertisement data using native peripheral mode
  Future<void> _broadcastAlert(SOSAlert alert) async {
    if (!_peripheralService.isSupported) {
      // Fall back to direct peer connections only
      _isAdvertising = true;
      notifyListeners();
      return;
    }

    // Convert SOSAlert to strict SOSBeacon
    final beacon = SOSBeacon(
      userId: alert.originatorDeviceId.hashCode, // 4 bytes
      sequence: 1, // Need proper sequence tracking in DB
      latitude: alert.location.latitude,
      longitude: alert.location.longitude,
      status: 1, // SOS
      timestamp: alert.originatedAt.millisecondsSinceEpoch ~/ 1000,
    );

    final success = await _peripheralService.startAdvertising(beacon);
    if (success) {
      _isAdvertising = true;
    } else {
      _eventController.add(BleErrorEvent(
        'Failed to start advertising: ${_peripheralService.lastError}',
      ));
    }
    notifyListeners();
  }

  /// Send alert to all connected peers
  Future<void> _sendToPeers(SOSAlert alert) async {
    // Deprecated: We primarily use advertising (Flood Mesh)
  }

  /// Connect to a peer and send alert
  Future<void> _connectAndSend(SOSAlert alert, PeerDevice peer) async {
    // Deprecated
  }

  /// Send alert to a specific peer
  Future<void> _sendAlertToPeer(SOSAlert alert, PeerDevice peer) async {
    // Deprecated
  }

  /// Stop broadcasting an SOS
  void stopSOS(String messageId) {
    _activeAlerts.remove(messageId);
    if (_activeAlerts.isEmpty) {
      _broadcastTimer?.cancel();
      _peripheralService.stopAdvertising();
      _isAdvertising = false;
      notifyListeners();
    }
  }

  /// Stop scanning
  void _stopScanning() {
    _scanTimer?.cancel();
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    _isScanning = false;
    notifyListeners();
  }

  /// Get status summary
  Map<String, dynamic> getStatus() {
    return {
      'isInitialized': _isInitialized,
      'isScanning': _isScanning,
      'isAdvertising': _isAdvertising,
      'totalPeers': _peers.length,
      'connectedPeers': _connectedPeerIds.length,
      'peersWithInternet': peersWithInternet.length,
      'activeAlerts': _activeAlerts.length,
    };
  }

  /// Dispose resources
  @override
  void dispose() {
    _scanTimer?.cancel();
    _broadcastTimer?.cancel();
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _peripheralEventSubscription?.cancel();
    _peripheralService.dispose();
    _eventController.close();
    _databaseService.close(); // Close DB

    // Disconnect all peers
    for (final peerId in _connectedPeerIds) {
      try {
        final peer = _peers[peerId];
        if (peer != null) {
          BluetoothDevice.fromId(peer.bleAddress).disconnect();
        }
      } catch (_) {}
    }

    super.dispose();
  }
}