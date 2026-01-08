import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import '../models/sos_packet.dart';
import '../models/sos_status.dart';
import '../utils/rssi_calculator.dart';
import 'packet_store.dart';
import 'connectivity_service.dart';

/// Connection state for BLE mesh networking
enum BLEConnectionState {
  unavailable,
  bluetoothOff,
  idle,
  broadcasting,
  scanning,
  meshActive,
}

/// BLE Service for cross-platform mesh networking
class BLEService {
  static const _channel = MethodChannel('com.project_flutter/ble');
  static const _eventChannel = EventChannel('com.project_flutter/ble_events');

  static BLEService? _instance;

  static BLEService get instance {
    _instance ??= BLEService._();
    return _instance!;
  }

  BLEService._() {
    _init();
  }

  // Stream controllers
  final _connectionStateController =
      StreamController<BLEConnectionState>.broadcast();
  final _packetReceivedController = StreamController<SOSPacket>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  // Services
  final PacketStore _packetStore = PacketStore.instance;
  final RSSICalculator _rssiCalculator = RSSICalculator();
  final ConnectivityChecker _connectivityChecker = ConnectivityChecker.instance;

  // State
  BLEConnectionState _state = BLEConnectionState.idle;
  bool _isLowPowerMode = false;
  int _connectedDevices = 0;
  SOSPacket? _currentBroadcast;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;

  // User data
  int? _userId;
  int _sequence = 0;

  // Broadcast queue (round-robin)
  final List<SOSPacket> _broadcastQueue = [];
  int _queueIndex = 0;

  /// Stream of connection state changes
  Stream<BLEConnectionState> get connectionState =>
      _connectionStateController.stream;

  /// Stream of received SOS packets
  Stream<SOSPacket> get onPacketReceived => _packetReceivedController.stream;

  /// Stream of error messages
  Stream<String> get onError => _errorController.stream;

  /// Current connection state
  BLEConnectionState get state => _state;

  /// Whether device is in low power mode
  bool get isLowPowerMode => _isLowPowerMode;

  /// Number of currently connected devices
  int get connectedDevices => _connectedDevices;

  /// RSSI calculator for distance
  RSSICalculator get rssiCalculator => _rssiCalculator;

  /// Initialize the BLE service
  void _init() {
    _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (dynamic error) {
        _errorController.add(error.toString());
      },
    );

    // Start cleanup timer (every 30 minutes)
    _cleanupTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _packetStore.deleteExpiredPackets();
    });

    // Load user data
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    _userId = await _packetStore.getUserId();
    _sequence = await _packetStore.getSequence();
  }

  /// Handle events from native BLE implementation
  void _handleNativeEvent(dynamic event) {
    if (event is! Map) return;

    final type = event['type'] as String?;
    final data = event['data'];

    switch (type) {
      case 'stateChanged':
        if (data is String) {
          _updateState(data);
        }
        break;
      case 'packetReceived':
        if (data is List) {
          final rssi = event['rssi'];
          _handlePacketReceived(data, rssi is int ? rssi : null);
        }
        break;
      case 'lowPowerModeChanged':
        if (data is bool) {
          _isLowPowerMode = data;
          if (_isLowPowerMode) {
            _errorController.add(
              'Low Power Mode enabled. Mesh may not work reliably.',
            );
          }
        }
        break;
      case 'connectedDevicesChanged':
        if (data is int) {
          _connectedDevices = data;
        }
        break;
      case 'error':
        if (data is String) {
          _errorController.add(data);
        }
        break;
    }
  }

  void _updateState(String stateString) {
    final newState = BLEConnectionState.values.firstWhere(
      (s) => s.name == stateString,
      orElse: () => BLEConnectionState.idle,
    );
    _state = newState;
    _connectionStateController.add(_state);
  }

  Future<void> _handlePacketReceived(List<dynamic> bytes, int? rssi) async {
    try {
      final packet = SOSPacket.fromBytes(bytes.cast<int>(), rssi: rssi);

      // Check expiry
      if (packet.isExpired) return;

      // Try to save (handles deduplication)
      final isNew = await _packetStore.savePacket(packet);

      if (isNew) {
        // Update RSSI tracking
        if (rssi != null) {
          _rssiCalculator.addSample(packet.userId.toRadixString(16), rssi);
        }

        // Emit to UI
        _packetReceivedController.add(packet);

        // Add to broadcast queue for relay
        _addToQueue(packet);
      }
    } catch (e) {
      _errorController.add('Failed to parse packet: $e');
    }
  }

  /// Add packet to broadcast queue
  void _addToQueue(SOSPacket packet) {
    // Don't relay our own packets
    if (packet.userId == _userId) return;

    // Don't relay SAFE packets multiple times
    if (packet.status == SOSStatus.safe) {
      _broadcastQueue.removeWhere((p) => p.userId == packet.userId);
    }

    // Add or update in queue
    final existingIndex = _broadcastQueue.indexWhere(
      (p) => p.userId == packet.userId,
    );
    if (existingIndex >= 0) {
      if (packet.sequence > _broadcastQueue[existingIndex].sequence) {
        _broadcastQueue[existingIndex] = packet;
      }
    } else {
      _broadcastQueue.add(packet);
    }
  }

  /// Start broadcasting own SOS
  Future<bool> startBroadcasting({
    required double latitude,
    required double longitude,
    required SOSStatus status,
  }) async {
    if (_userId == null) await _loadUserData();

    _sequence = await _packetStore.incrementSequence();

    _currentBroadcast = SOSPacket.create(
      userId: _userId!,
      sequence: _sequence,
      latitude: latitude,
      longitude: longitude,
      status: status,
    );

    // Add self to front of queue
    _broadcastQueue.insert(0, _currentBroadcast!);

    // Start round-robin broadcasting
    _startBroadcastLoop();

    try {
      final result = await _channel.invokeMethod<bool>('startBroadcasting', {
        'packet': _currentBroadcast!.toBytes(),
      });
      return result ?? false;
    } on PlatformException catch (e) {
      _errorController.add('Failed to start broadcasting: ${e.message}');
      return false;
    }
  }

  /// Start round-robin broadcast loop
  void _startBroadcastLoop() {
    _broadcastTimer?.cancel();

    // Broadcast every 300ms, cycling through queue
    _broadcastTimer = Timer.periodic(const Duration(milliseconds: 300), (
      timer,
    ) async {
      if (_broadcastQueue.isEmpty) return;

      // Get next packet in queue
      _queueIndex = (_queueIndex + 1) % _broadcastQueue.length;
      final packet = _broadcastQueue[_queueIndex];

      // Add random delay to prevent jamming (0-500ms)
      await Future.delayed(Duration(milliseconds: Random().nextInt(500)));

      // Broadcast
      try {
        await _channel.invokeMethod<bool>('startBroadcasting', {
          'packet': packet.toBytes(),
        });
      } catch (_) {}
    });
  }

  /// Stop broadcasting
  Future<bool> stopBroadcasting() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;

    // If we were broadcasting SOS, send SAFE
    if (_currentBroadcast != null &&
        _currentBroadcast!.status != SOSStatus.safe) {
      final safePacket = _currentBroadcast!.markSafe();
      _broadcastQueue.insert(0, safePacket);

      try {
        await _channel.invokeMethod<bool>('startBroadcasting', {
          'packet': safePacket.toBytes(),
        });

        // Brief delay to let SAFE propagate
        await Future.delayed(const Duration(seconds: 2));
      } catch (_) {}
    }

    _broadcastQueue.removeWhere((p) => p.userId == _userId);
    _currentBroadcast = null;

    try {
      final result = await _channel.invokeMethod<bool>('stopBroadcasting');
      return result ?? false;
    } on PlatformException catch (e) {
      _errorController.add('Failed to stop broadcasting: ${e.message}');
      return false;
    }
  }

  /// Start scanning for other SOS beacons
  Future<bool> startScanning() async {
    try {
      final result = await _channel.invokeMethod<bool>('startScanning');
      return result ?? false;
    } on PlatformException catch (e) {
      _errorController.add('Failed to start scanning: ${e.message}');
      return false;
    }
  }

  /// Stop scanning
  Future<bool> stopScanning() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopScanning');
      return result ?? false;
    } on PlatformException catch (e) {
      _errorController.add('Failed to stop scanning: ${e.message}');
      return false;
    }
  }

  /// Start full mesh mode
  Future<bool> startMeshMode({
    required double latitude,
    required double longitude,
    required SOSStatus status,
  }) async {
    final broadcastOk = await startBroadcasting(
      latitude: latitude,
      longitude: longitude,
      status: status,
    );
    final scanOk = await startScanning();
    return broadcastOk && scanOk;
  }

  /// Stop all BLE operations
  Future<void> stopAll() async {
    await stopBroadcasting();
    await stopScanning();
  }

  /// Check if internet is available
  Future<bool> checkInternetConnection() async {
    return _connectivityChecker.checkInternet();
  }

  /// Get device UUID
  Future<String?> getDeviceUuid() async {
    try {
      return await _channel.invokeMethod<String>('getDeviceUuid');
    } on PlatformException {
      return null;
    }
  }

  /// Check if device supports BLE 5.0
  /// Returns true on iOS (iOS devices support BLE 5), and checks hardware on Android
  Future<bool> supportsBle5() async {
    try {
      final result = await _channel.invokeMethod<bool>('supportsBle5');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Get user ID
  Future<int> getUserId() async {
    if (_userId == null) await _loadUserData();
    return _userId!;
  }

  /// Get all active SOS packets from local storage
  Future<List<SOSPacket>> getActivePackets() async {
    return _packetStore.getActivePackets();
  }

  /// Get unsynced packets for cloud upload
  Future<List<SOSPacket>> getUnsyncedPackets() async {
    return _packetStore.getUnsyncedPackets();
  }

  /// Dispose resources
  void dispose() {
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _connectionStateController.close();
    _packetReceivedController.close();
    _errorController.close();
  }
}
