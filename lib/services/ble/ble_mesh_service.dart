/// BLE Mesh Service
/// Handles Bluetooth Low Energy mesh networking for SOS relay

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/sos_alert.dart';
import '../../models/peer_device.dart';
import '../../models/device_info.dart';
import '../crypto/encryption_service.dart';

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
  Timer? _scanTimer;
  Timer? _broadcastTimer;

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
      await FlutterBluePlus.startScan(
        timeout: config.scanDuration,
        withServices: [Guid(BleUuids.serviceUuid)],
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
    final deviceId = _extractDeviceId(result);
    if (deviceId == null || deviceId == localDevice?.deviceId) return;

    final existingPeer = _peers[deviceId];

    if (existingPeer != null) {
      existingPeer.updateFromAdvertisement(
        rssi: result.rssi,
        hasInternet: _extractHasInternet(result),
      );
    } else {
      final peer = PeerDevice(
        deviceId: deviceId,
        bleAddress: result.device.remoteId.str,
        name: result.device.platformName,
        rssi: result.rssi,
        hasInternet: _extractHasInternet(result),
      );
      _peers[deviceId] = peer;
      _eventController.add(PeerDiscoveredEvent(peer));
    }

    // Check for SOS alerts in advertisement data
    _checkForSosInAdvertisement(result);

    notifyListeners();
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
    final manufacturerData = result.advertisementData.manufacturerData;
    if (manufacturerData.isNotEmpty) {
      final data = manufacturerData.values.first;
      if (data.length > 8) {
        return data[8] == 1;
      }
    }
    return false;
  }

  /// Check for SOS alerts in advertisement data
  void _checkForSosInAdvertisement(ScanResult result) {
    final serviceData = result.advertisementData.serviceData;
    final sosServiceGuid = Guid(BleUuids.sosAlertUuid);

    if (serviceData.containsKey(sosServiceGuid)) {
      final data = serviceData[sosServiceGuid]!;
      _processReceivedSosData(data, result.device.remoteId.str);
    }
  }

  /// Process received SOS data
  void _processReceivedSosData(List<int> data, String fromAddress) {
    try {
      final alert = SOSAlert.fromBytes(data);
      if (alert == null) return;

      // Skip if already processed
      if (_processedMessageIds.contains(alert.messageId)) return;
      _processedMessageIds.add(alert.messageId);

      // Skip if expired
      if (alert.isExpired) return;

      // Skip if max hops reached
      if (alert.hopCount >= config.maxRelayHops) return;

      final peer = _peers.values.firstWhere(
        (p) => p.bleAddress == fromAddress,
        orElse: () => PeerDevice(
          deviceId: 'unknown',
          bleAddress: fromAddress,
        ),
      );

      peer.recordMessage(received: true);
      _eventController.add(MessageReceivedEvent(alert, peer));
    } catch (e) {
      // Ignore malformed data
    }
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

    // Also try to connect and send to nearby peers directly
    await _sendToPeers(alert);
  }

  /// Broadcast alert in advertisement data
  Future<void> _broadcastAlert(SOSAlert alert) async {
    // Note: flutter_blue_plus doesn't support peripheral mode directly
    // This would require platform-specific implementation
    // For now, we rely on sending to connected peers

    _isAdvertising = true;
    notifyListeners();
  }

  /// Send alert to all connected peers
  Future<void> _sendToPeers(SOSAlert alert) async {
    for (final peer in _peers.values) {
      if (peer.connectionState == PeerConnectionState.connected) {
        await _sendAlertToPeer(alert, peer);
      } else {
        // Try to connect
        await _connectAndSend(alert, peer);
      }
    }
  }

  /// Connect to a peer and send alert
  Future<void> _connectAndSend(SOSAlert alert, PeerDevice peer) async {
    try {
      final device = BluetoothDevice.fromId(peer.bleAddress);

      peer.connectionState = PeerConnectionState.connecting;
      notifyListeners();

      await device.connect(timeout: const Duration(seconds: 5));
      _connectedPeerIds.add(peer.deviceId);
      peer.connectionState = PeerConnectionState.connected;
      notifyListeners();

      await _sendAlertToPeer(alert, peer);
    } catch (e) {
      peer.connectionState = PeerConnectionState.error;
      notifyListeners();
    }
  }

  /// Send alert to a specific peer
  Future<void> _sendAlertToPeer(SOSAlert alert, PeerDevice peer) async {
    try {
      final device = BluetoothDevice.fromId(peer.bleAddress);
      final services = await device.discoverServices();

      for (final service in services) {
        if (service.uuid.toString() == BleUuids.serviceUuid) {
          for (final char in service.characteristics) {
            if (char.uuid.toString() == BleUuids.sosAlertUuid) {
              // Send the alert
              final alertForRelay = alert.copyForRelay(
                localDevice?.deviceId ?? 'unknown',
                false, // hasInternet determined by connectivity service
              );
              await char.write(alertForRelay.toBytes());

              peer.recordMessage(sent: true);
              _eventController.add(MessageRelayedEvent(
                alert.messageId,
                peer.deviceId,
              ));
            }
          }
        }
      }
    } catch (e) {
      _eventController.add(BleErrorEvent('Failed to send to peer', e));
    }
  }

  /// Stop broadcasting an SOS
  void stopSOS(String messageId) {
    _activeAlerts.remove(messageId);
    if (_activeAlerts.isEmpty) {
      _broadcastTimer?.cancel();
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
    _eventController.close();

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
