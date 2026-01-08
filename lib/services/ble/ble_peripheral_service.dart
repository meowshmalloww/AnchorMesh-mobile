// BLE Peripheral Service
// Platform channel for native BLE advertising/peripheral mode

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Compact SOS beacon data for BLE advertising
/// Strict 21-byte format for Legacy Advertising (31-byte limit)
class SOSBeacon {
  static const int appHeader = 0xFFFF; // 2 bytes

  final int userId;            // 4 bytes
  final int sequence;          // 2 bytes
  final double latitude;       // 4 bytes (int encoded)
  final double longitude;      // 4 bytes (int encoded)
  final int status;            // 1 byte
  final int timestamp;         // 4 bytes (Unix seconds)

  SOSBeacon({
    required this.userId,
    required this.sequence,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.timestamp,
  });

  /// Convert to bytes (21 bytes strict)
  List<int> toBytes() {
    final buffer = ByteData(21);
    int offset = 0;

    // 0-1: App Header (0xFFFF)
    buffer.setUint16(offset, appHeader, Endian.big);
    offset += 2;

    // 2-5: User ID (4 Bytes)
    buffer.setUint32(offset, userId, Endian.big);
    offset += 4;

    // 6-7: Sequence (2 Bytes)
    buffer.setUint16(offset, sequence, Endian.big);
    offset += 2;

    // 8-11: Latitude (4 Bytes) -> Lat * 10^6
    buffer.setInt32(offset, (latitude * 1000000).round(), Endian.big);
    offset += 4;

    // 12-15: Longitude (4 Bytes) -> Lon * 10^6
    buffer.setInt32(offset, (longitude * 1000000).round(), Endian.big);
    offset += 4;

    // 16: Status (1 Byte)
    buffer.setUint8(offset, status);
    offset += 1;

    // 17-20: Timestamp (4 Bytes)
    buffer.setUint32(offset, timestamp, Endian.big);
    
    return buffer.buffer.asUint8List().toList();
  }

  /// Parse from bytes
  static SOSBeacon? fromBytes(List<int> bytes) {
    if (bytes.length < 21) return null;

    try {
      final buffer = ByteData.sublistView(Uint8List.fromList(bytes));
      int offset = 0;

      // Check Header
      final header = buffer.getUint16(offset, Endian.big);
      if (header != appHeader) return null;
      offset += 2;

      final userId = buffer.getUint32(offset, Endian.big);
      offset += 4;

      final sequence = buffer.getUint16(offset, Endian.big);
      offset += 2;

      final latInt = buffer.getInt32(offset, Endian.big);
      final latitude = latInt / 1000000.0;
      offset += 4;

      final lonInt = buffer.getInt32(offset, Endian.big);
      final longitude = lonInt / 1000000.0;
      offset += 4;

      final status = buffer.getUint8(offset);
      offset += 1;

      final timestamp = buffer.getUint32(offset, Endian.big);

      return SOSBeacon(
        userId: userId,
        sequence: sequence,
        latitude: latitude,
        longitude: longitude,
        status: status,
        timestamp: timestamp,
      );
    } catch (e) {
      return null;
    }
  }
}

/// BLE Peripheral advertising state
enum AdvertisingState {
  stopped,
  starting,
  advertising,
  error,
}

/// Events from native BLE peripheral
abstract class BlePeripheralEvent {}

class AdvertisingStartedEvent extends BlePeripheralEvent {}

class AdvertisingStoppedEvent extends BlePeripheralEvent {}

class AdvertisingErrorEvent extends BlePeripheralEvent {
  final String message;
  AdvertisingErrorEvent(this.message);
}

class BeaconReceivedEvent extends BlePeripheralEvent {
  final SOSBeacon beacon;
  final int rssi;
  final String deviceAddress;
  BeaconReceivedEvent(this.beacon, this.rssi, this.deviceAddress);
}

class PeerConnectedEvent extends BlePeripheralEvent {
  final String deviceAddress;
  PeerConnectedEvent(this.deviceAddress);
}

class DataReceivedEvent extends BlePeripheralEvent {
  final String deviceAddress;
  final List<int> data;
  DataReceivedEvent(this.deviceAddress, this.data);
}

/// BLE Peripheral Service - handles native advertising via platform channels
class BLEPeripheralService extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('com.sosapp/ble_peripheral');
  static const EventChannel _eventChannel = EventChannel('com.sosapp/ble_peripheral_events');

  static final BLEPeripheralService _instance = BLEPeripheralService._internal();
  factory BLEPeripheralService() => _instance;

  BLEPeripheralService._internal() {
    _setupEventListener();
  }

  // State
  AdvertisingState _state = AdvertisingState.stopped;
  bool _isSupported = false;
  bool _isInitialized = false;
  String? _lastError;

  // Event stream
  final _eventController = StreamController<BlePeripheralEvent>.broadcast();
  StreamSubscription? _nativeEventSubscription;

  // Processed beacons to avoid duplicates
  final Set<String> _processedBeaconHashes = {};
  final Duration _beaconExpiryDuration = const Duration(minutes: 5);
  final Map<String, DateTime> _beaconTimestamps = {};

  /// Event stream
  Stream<BlePeripheralEvent> get events => _eventController.stream;

  /// Current advertising state
  AdvertisingState get state => _state;

  /// Whether BLE peripheral mode is supported
  bool get isSupported => _isSupported;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Whether currently advertising
  bool get isAdvertising => _state == AdvertisingState.advertising;

  /// Last error message
  String? get lastError => _lastError;

  /// Setup event listener from native side
  void _setupEventListener() {
    _nativeEventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (error) {
        _lastError = error.toString();
        _state = AdvertisingState.error;
        _eventController.add(AdvertisingErrorEvent(error.toString()));
        notifyListeners();
      },
    );
  }

  /// Handle events from native code
  void _handleNativeEvent(dynamic event) {
    if (event is! Map) return;

    final type = event['type'] as String?;
    switch (type) {
      case 'advertisingStarted':
        _state = AdvertisingState.advertising;
        _eventController.add(AdvertisingStartedEvent());
        notifyListeners();
        break;

      case 'advertisingStopped':
        _state = AdvertisingState.stopped;
        _eventController.add(AdvertisingStoppedEvent());
        notifyListeners();
        break;

      case 'advertisingError':
        _state = AdvertisingState.error;
        _lastError = event['message'] as String?;
        _eventController.add(AdvertisingErrorEvent(_lastError ?? 'Unknown error'));
        notifyListeners();
        break;

      case 'beaconReceived':
        _handleReceivedBeacon(event);
        break;

      case 'peerConnected':
        final address = event['deviceAddress'] as String;
        _eventController.add(PeerConnectedEvent(address));
        break;

      case 'dataReceived':
        final address = event['deviceAddress'] as String;
        final data = (event['data'] as List).cast<int>();
        _eventController.add(DataReceivedEvent(address, data));
        break;
    }
  }

  /// Handle received beacon and check for duplicates
  void _handleReceivedBeacon(Map<dynamic, dynamic> event) {
    final data = (event['data'] as List?)?.cast<int>();
    if (data == null) return;

    final beacon = SOSBeacon.fromBytes(data);
    if (beacon == null) return;

    // Create unique hash for deduplication using userId and sequence
    final hash = '${beacon.userId}_${beacon.sequence}';

    // Clean up old entries
    _cleanupExpiredBeacons();

    // Skip if already processed recently
    if (_processedBeaconHashes.contains(hash)) return;

    _processedBeaconHashes.add(hash);
    _beaconTimestamps[hash] = DateTime.now();

    final rssi = event['rssi'] as int? ?? -100;
    final address = event['deviceAddress'] as String? ?? 'unknown';

    _eventController.add(BeaconReceivedEvent(beacon, rssi, address));
  }

  /// Clean up expired beacon entries
  void _cleanupExpiredBeacons() {
    final now = DateTime.now();
    final expiredHashes = <String>[];

    _beaconTimestamps.forEach((hash, timestamp) {
      if (now.difference(timestamp) > _beaconExpiryDuration) {
        expiredHashes.add(hash);
      }
    });

    for (final hash in expiredHashes) {
      _processedBeaconHashes.remove(hash);
      _beaconTimestamps.remove(hash);
    }
  }

  /// Initialize the BLE peripheral service
  Future<bool> initialize() async {
    if (_isInitialized) return _isSupported;

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('initialize');
      _isSupported = result?['supported'] as bool? ?? false;
      _isInitialized = true;
      notifyListeners();
      return _isSupported;
    } on PlatformException catch (e) {
      _lastError = e.message;
      _isInitialized = true;
      _isSupported = false;
      notifyListeners();
      return false;
    }
  }

  /// Start advertising an SOS beacon
  Future<bool> startAdvertising(SOSBeacon beacon) async {
    if (!_isSupported) {
      _lastError = 'BLE peripheral mode not supported';
      return false;
    }

    if (_state == AdvertisingState.advertising) {
      // Update existing advertisement
      return await updateAdvertisement(beacon);
    }

    _state = AdvertisingState.starting;
    notifyListeners();

    try {
      final result = await _channel.invokeMethod<bool>('startAdvertising', {
        'data': beacon.toBytes(),
        'serviceUuid': '0000sos0-0000-1000-8000-00805f9b34fb',
        'localName': 'SOS-${beacon.userId.toRadixString(16).padLeft(4, '0').substring(0, 4)}',
      });

      if (result == true) {
        _state = AdvertisingState.advertising;
      } else {
        _state = AdvertisingState.error;
        _lastError = 'Failed to start advertising';
      }

      notifyListeners();
      return result == true;
    } on PlatformException catch (e) {
      _state = AdvertisingState.error;
      _lastError = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Update the advertisement data
  Future<bool> updateAdvertisement(SOSBeacon beacon) async {
    if (!_isSupported || _state != AdvertisingState.advertising) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('updateAdvertisement', {
        'data': beacon.toBytes(),
      });
      return result == true;
    } on PlatformException catch (e) {
      _lastError = e.message;
      return false;
    }
  }

  /// Stop advertising
  Future<void> stopAdvertising() async {
    if (_state != AdvertisingState.advertising) return;

    try {
      await _channel.invokeMethod<void>('stopAdvertising');
      _state = AdvertisingState.stopped;
      notifyListeners();
    } on PlatformException catch (e) {
      _lastError = e.message;
    }
  }

  /// Send data to a connected peer via GATT
  Future<bool> sendDataToPeer(String deviceAddress, List<int> data) async {
    try {
      final result = await _channel.invokeMethod<bool>('sendData', {
        'deviceAddress': deviceAddress,
        'data': data,
      });
      return result == true;
    } on PlatformException catch (e) {
      _lastError = e.message;
      return false;
    }
  }

  /// Get service status
  Map<String, dynamic> getStatus() {
    return {
      'isSupported': _isSupported,
      'isInitialized': _isInitialized,
      'state': _state.name,
      'isAdvertising': isAdvertising,
      'lastError': _lastError,
      'processedBeacons': _processedBeaconHashes.length,
    };
  }

  /// Dispose resources
  @override
  void dispose() {
    _nativeEventSubscription?.cancel();
    _eventController.close();
    stopAdvertising();
    super.dispose();
  }
}
