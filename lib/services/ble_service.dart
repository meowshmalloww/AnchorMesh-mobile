import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/sos_packet.dart';
import '../models/sos_status.dart';
import '../models/ble_models.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/rssi_calculator.dart';
import 'packet_store.dart';
import 'connectivity_service.dart';

// Re-export for backward compatibility
export '../models/ble_models.dart';

/// BLE Service for cross-platform mesh networking
class BLEService {
  static const _channel = MethodChannel('com.project_flutter/ble');
  static const _eventChannel = EventChannel('com.project_flutter/ble_events');

  static BLEService? _instance;

  static BLEService get instance {
    _instance ??= BLEService._();
    return _instance!;
  }

  /// Reset singleton instance for app restart (iOS force quit recovery)
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  BLEService._() {
    _init();
  }

  // Stream controllers
  final _connectionStateController =
      StreamController<BLEConnectionState>.broadcast();
  final _packetReceivedController = StreamController<SOSPacket>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _echoController = StreamController<EchoEvent>.broadcast();
  final _verificationController =
      StreamController<VerificationStatus>.broadcast();
  final _handshakeController = StreamController<int>.broadcast();
  final _rawDeviceController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Services
  final PacketStore _packetStore = PacketStore.instance;
  final RSSICalculator _rssiCalculator = RSSICalculator();
  final ConnectivityChecker _connectivityChecker = ConnectivityChecker.instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Event channel subscription (must be tracked for cleanup)
  StreamSubscription? _eventChannelSubscription;

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

  // Echo detection - tracks when our packets are seen being relayed
  int _echoCount = 0;
  final Set<int> _echoSources = {};

  // Handshake counter - number of successful relays
  int _handshakeCount = 0;

  // Verification tracking - which devices have confirmed each SOS
  final Map<int, Set<int>> _verificationMap = {};

  // Seen packet IDs to prevent rebroadcast loops
  final Set<String> _seenPacketIds = {};

  // Broadcast priority tracking
  int _broadcastTick = 0;

  /// Stream of connection state changes
  Stream<BLEConnectionState> get connectionState =>
      _connectionStateController.stream;

  /// Stream of received SOS packets
  Stream<SOSPacket> get onPacketReceived => _packetReceivedController.stream;

  /// Stream of error messages
  Stream<String> get onError => _errorController.stream;

  /// Stream of echo events (when our packet is detected being relayed)
  Stream<EchoEvent> get onEchoDetected => _echoController.stream;

  /// Stream of verification status updates
  Stream<VerificationStatus> get onVerificationUpdate =>
      _verificationController.stream;

  /// Stream of handshake count updates
  Stream<int> get onHandshakeUpdate => _handshakeController.stream;

  /// Stream of raw BLE devices (for nRF Connect-like scanning)
  Stream<Map<String, dynamic>> get onRawDeviceFound =>
      _rawDeviceController.stream;

  /// Current connection state
  BLEConnectionState get state => _state;

  /// Whether device is in low power mode
  bool get isLowPowerMode => _isLowPowerMode;

  /// Number of currently connected devices
  int get connectedDevices => _connectedDevices;

  /// RSSI calculator for distance
  RSSICalculator get rssiCalculator => _rssiCalculator;

  /// Number of times our packet was echoed back
  int get echoCount => _echoCount;

  /// Number of unique devices that relayed our packet
  int get echoSources => _echoSources.length;

  /// Number of successful handshakes (packet relays)
  int get handshakeCount => _handshakeCount;

  /// Initialize the BLE service
  void _init() {
    // Cancel existing subscription if any (handles reinit)
    _eventChannelSubscription?.cancel();

    // Subscribe to native BLE events
    _eventChannelSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (dynamic error) {
        _errorController.add(error.toString());
      },
      onDone: () {
        debugPrint('BLE event channel closed');
      },
    );

    // Start cleanup timer (every 30 minutes)
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _packetStore.deleteExpiredPackets();
      _cleanupSeenPackets();
    });

    // Load user data
    _loadUserData();

    // Initialize notifications
    _initNotifications();
  }

  /// Reinitialize event channel after app resume (handles stale channel)
  void reinitializeEventChannel() {
    debugPrint('Reinitializing BLE event channel');
    _eventChannelSubscription?.cancel();
    _eventChannelSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (dynamic error) {
        _errorController.add(error.toString());
      },
      onDone: () {
        debugPrint('BLE event channel closed');
      },
    );
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(settings);

    // Create channel for Android
    const androidChannel = AndroidNotificationChannel(
      'sos_alerts',
      'SOS Alerts',
      description: 'High priority alerts for incoming SOS signals',
      importance: Importance.max,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> _showNotification(SOSPacket packet) async {
    // Don't notify for SAFE or own packets
    if (packet.status == SOSStatus.safe || packet.userId == _userId) return;

    final title = 'SOS DETECTED: ${packet.status.description}';
    final body =
        'Signal from user ${packet.userId.toRadixString(16).toUpperCase()}';

    const androidDetails = AndroidNotificationDetails(
      'sos_alerts',
      'SOS Alerts',
      channelDescription: 'High priority alerts for incoming SOS signals',
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFFFF0000), // Red
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      packet.uniqueId.hashCode,
      title,
      body,
      details,
    );
  }

  void _cleanupSeenPackets() {
    // Keep only recent packet IDs to prevent memory bloat
    if (_seenPacketIds.length > 1000) {
      final toRemove = _seenPacketIds
          .take(_seenPacketIds.length - 500)
          .toList();
      for (final id in toRemove) {
        _seenPacketIds.remove(id);
      }
    }
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
      case 'rawDeviceFound':
        if (data is Map) {
          _rawDeviceController.add(Map<String, dynamic>.from(data));
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

      // Create unique packet ID for deduplication
      final packetId = '${packet.userId}-${packet.sequence}';

      // ECHO DETECTION: Check if this is our own packet being relayed back
      if (packet.userId == _userId) {
        _handleEchoDetected(packet, rssi ?? -80);
        return; // Don't process our own packets further
      }

      // Check if this is a SAFE packet - stop propagation for this user
      if (packet.status == SOSStatus.safe) {
        _handleSafePacket(packet);
        return;
      }

      // Check if we've already seen this exact packet
      if (_seenPacketIds.contains(packetId)) {
        // Still count as verification if from different source
        if (_userId != null) {
          _addVerification(packet.userId, _userId!);
        }
        return;
      }
      _seenPacketIds.add(packetId);

      // Try to save (handles deduplication)
      final isNew = await _packetStore.savePacket(packet);

      if (isNew) {
        // Update RSSI tracking
        if (rssi != null) {
          _rssiCalculator.addSample(packet.userId.toRadixString(16), rssi);
        }

        // Emit to UI - ONLY if broadcast (0) or targeted to us
        if (packet.targetId == 0 || packet.targetId == _userId) {
          _packetReceivedController.add(packet);
        } else {
          debugPrint(
            'Relaying targeted message for ${packet.targetId.toRadixString(16)}',
          );
        }

        // Add to broadcast queue for relay
        _addToQueue(packet);

        // Increment handshake counter
        _handshakeCount++;
        _handshakeController.add(_handshakeCount);

        // Add verification (we received it, so we confirm it)
        if (_userId != null) {
          _addVerification(packet.userId, _userId!);
        }

        // Show Notification
        if (packet.targetId == 0 || packet.targetId == _userId) {
          _showNotification(packet);
        }
      }
    } catch (e) {
      _errorController.add('Failed to parse packet: $e');
    }
  }

  /// Handle echo detection - our packet seen being relayed
  void _handleEchoDetected(SOSPacket packet, int rssi) {
    _echoCount++;
    // Track the source (we can't know exactly who, but we know it's not us)
    // In real implementation, you'd track the BLE address
    _echoSources.add(rssi.hashCode ^ DateTime.now().millisecondsSinceEpoch);

    final event = EchoEvent(
      userId: packet.userId,
      rssi: rssi,
      timestamp: DateTime.now(),
    );
    _echoController.add(event);

    debugPrint(
      'ECHO detected! Count: $_echoCount from ${_echoSources.length} sources',
    );
  }

  /// Handle SAFE packet - stop propagation
  void _handleSafePacket(SOSPacket packet) {
    // Remove this user from broadcast queue
    _broadcastQueue.removeWhere((p) => p.userId == packet.userId);

    // Remove from verification tracking
    _verificationMap.remove(packet.userId);

    // Still save and emit to UI
    _packetStore.savePacket(packet);
    _packetReceivedController.add(packet);

    debugPrint(
      'SAFE packet received for user ${packet.userId.toRadixString(16)} - stopping propagation',
    );
  }

  /// Add verification for an SOS signal
  void _addVerification(int sosUserId, int confirmingDeviceId) {
    _verificationMap.putIfAbsent(sosUserId, () => {});
    _verificationMap[sosUserId]!.add(confirmingDeviceId);

    final confirmations = _verificationMap[sosUserId]!.length;
    final isVerified =
        confirmations >= VerificationStatus.requiredConfirmations;

    final status = VerificationStatus(
      userId: sosUserId,
      confirmations: confirmations,
      isVerified: isVerified,
      confirmingDevices: _verificationMap[sosUserId]!.toList(),
    );

    _verificationController.add(status);

    if (isVerified) {
      debugPrint(
        'SOS from ${sosUserId.toRadixString(16)} VERIFIED by $confirmations devices',
      );
    }
  }

  /// Get verification status for a user
  VerificationStatus? getVerificationStatus(int userId) {
    final confirmingDevices = _verificationMap[userId];
    if (confirmingDevices == null) return null;

    return VerificationStatus(
      userId: userId,
      confirmations: confirmingDevices.length,
      isVerified:
          confirmingDevices.length >= VerificationStatus.requiredConfirmations,
      confirmingDevices: confirmingDevices.toList(),
    );
  }

  /// Add packet to broadcast queue
  void _addToQueue(SOSPacket packet) {
    // Don't relay our own packets
    if (packet.userId == _userId) return;

    // Don't relay SAFE packets (they stop propagation)
    if (packet.status == SOSStatus.safe) {
      _broadcastQueue.removeWhere((p) => p.userId == packet.userId);
      return;
    }

    // Check for congestion
    if (_broadcastQueue.length > 100) {
      if (_broadcastQueue.length % 50 == 0) {
        _errorController.add('Network congestion: dropping oldest relays.');
      }

      // Drop oldest forwarded packet (from the end of the list)
      // We protect index 0 if it's us, but we generally relay from end.
      // Actually relay logic iterates.
      // Simple strategy: Remove last item.
      _broadcastQueue.removeLast();
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
  /// Start broadcasting own SOS
  Future<bool> startBroadcasting({
    required double latitude,
    required double longitude,
    required SOSStatus status,
  }) async {
    if (_userId == null) await _loadUserData();

    // Check BLE 5 support
    final hasBle5 = await supportsBle5();

    // Get user preference from settings (stored as string in DB)
    final db = await _packetStore.database;
    final res = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: ['ble_version'],
    );
    final prefVersion = res.isNotEmpty
        ? res.first['value'] as String
        : 'legacy';

    // Determine mode: Force Legacy if device doesn't support BLE 5
    final useExtended = hasBle5 && prefVersion == 'modern';

    _sequence = await _packetStore.incrementSequence();

    // Reset echo tracking regarding new broadcast
    _echoCount = 0;
    _echoSources.clear();
    _handshakeCount = 0;

    _currentBroadcast = SOSPacket.create(
      userId: _userId!,
      sequence: _sequence,
      latitude: latitude,
      longitude: longitude,
      status: status,
    );

    debugPrint(
      'Starting Broadcast: Lat: $latitude, Lon: $longitude, Status: ${status.name}',
    );

    // Add self to front of queue
    _broadcastQueue.insert(0, _currentBroadcast!);

    // Start round-robin broadcasting
    _startBroadcastLoop(useExtended: useExtended);

    try {
      final result = await _channel.invokeMethod<bool>('startBroadcasting', {
        'packet': _currentBroadcast!.toBytes(),
        'extended': useExtended, // Tell native to use Extended Adv
      });
      return result ?? false;
    } on PlatformException catch (e) {
      _errorController.add('Failed to start broadcasting: ${e.message}');
      return false;
    }
  }

  /// Send a targeted message to a specific user
  Future<bool> sendTargetMessage({
    required int targetUserId,
    required double latitude,
    required double longitude,
    required SOSStatus status,
  }) async {
    if (_userId == null) await _loadUserData();

    _sequence = await _packetStore.incrementSequence();

    final packet = SOSPacket.create(
      userId: _userId!,
      sequence: _sequence,
      latitude: latitude,
      longitude: longitude,
      status: status,
      targetId: targetUserId,
    );

    // Add to broadcast queue
    _addToQueue(packet);

    // Save locally (marked as local origin - will NEVER be synced to cloud)
    // Only devices that receive this via BLE can relay it to the dashboard
    await _packetStore.saveLocalPacket(packet);

    // Trigger immediate broadcast attempt
    try {
      await _channel.invokeMethod<bool>('startBroadcasting', {
        'packet': packet.toBytes(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Start round-robin broadcast loop with smart prioritization
  void _startBroadcastLoop({bool useExtended = false}) {
    _broadcastTimer?.cancel();
    _broadcastTick = 0;

    // Broadcast every 1500ms, cycling through queue
    // 300ms was too fast for some iOS radio stacks, causing freezes/crashes
    _broadcastTimer = Timer.periodic(const Duration(milliseconds: 1500), (
      timer,
    ) async {
      _broadcastTick++;

      SOSPacket? packetToBroadcast;

      // PRIORITY RULE 1: Broadcast own SOS 50% of the time (every even tick)
      if (_broadcastTick % 2 == 0 && _currentBroadcast != null) {
        packetToBroadcast = _currentBroadcast;
      } else {
        // Broadcast relayed packets in other slots
        if (_broadcastQueue.isNotEmpty) {
          // Queue filter: Don't relay own packet again here
          final relayCandidates = _broadcastQueue
              .where((p) => p.userId != _userId)
              .toList();

          if (relayCandidates.isNotEmpty) {
            _queueIndex = (_queueIndex + 1) % relayCandidates.length;
            packetToBroadcast = relayCandidates[_queueIndex];
          } else if (_currentBroadcast != null) {
            // Fallback to own packet if queue empty
            packetToBroadcast = _currentBroadcast;
          }
        } else if (_currentBroadcast != null) {
          packetToBroadcast = _currentBroadcast;
        }
      }

      if (packetToBroadcast == null) return;

      // ANTI-JAMMING: Random delay before rebroadcast (0-500ms)
      await Future.delayed(Duration(milliseconds: Random().nextInt(500)));

      // Broadcast
      try {
        await _channel.invokeMethod<bool>('startBroadcasting', {
          'packet': packetToBroadcast.toBytes(),
          'extended': useExtended,
        });
      } catch (_) {}
    });
  }

  /// Stop broadcasting and send SAFE packet
  Future<bool> stopBroadcasting() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;

    // If we were broadcasting SOS, send SAFE to stop propagation
    if (_currentBroadcast != null &&
        _currentBroadcast!.status != SOSStatus.safe &&
        _userId != null) {
      _sequence = await _packetStore.incrementSequence();
      final safePacket = SOSPacket.create(
        userId: _userId!,
        sequence: _sequence,
        latitude: _currentBroadcast!.latitude,
        longitude: _currentBroadcast!.longitude,
        status: SOSStatus.safe,
      );

      try {
        // Broadcast SAFE packet multiple times to ensure propagation
        for (int i = 0; i < 5; i++) {
          await _channel.invokeMethod<bool>('startBroadcasting', {
            'packet': safePacket.toBytes(),
          });
          await Future.delayed(const Duration(milliseconds: 200));
        }
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
  Future<bool> supportsBle5() async {
    try {
      final result = await _channel.invokeMethod<bool>('supportsBle5');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Check if WiFi is enabled (potential interference)
  Future<bool> checkWifiStatus() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkWifiStatus');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Start raw BLE scan (nRF Connect-like, no UUID filtering)
  /// Returns device info via onRawDeviceFound stream
  Future<bool> startRawScan() async {
    try {
      final result = await _channel.invokeMethod<bool>('startRawScan');
      return result ?? false;
    } on PlatformException catch (e) {
      _errorController.add('Failed to start raw scan: ${e.message}');
      return false;
    }
  }

  /// Stop raw BLE scan
  Future<bool> stopRawScan() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopRawScan');
      return result ?? false;
    } on PlatformException catch (e) {
      _errorController.add('Failed to stop raw scan: ${e.message}');
      return false;
    }
  }

  /// Test notification by simulating an SOS packet reception
  /// This is for testing purposes only - triggers a notification without BLE
  Future<bool> testNotification() async {
    try {
      final result = await _channel.invokeMethod<bool>('testNotification');
      return result ?? false;
    } on PlatformException catch (e) {
      _errorController.add('Test notification failed: ${e.message}');
      return false;
    }
  }

  /// Get user ID
  Future<int> getUserId() async {
    if (_userId == null) {
      await _loadUserData();
    }
    // _loadUserData always sets _userId, but add fallback for safety
    return _userId ?? await _packetStore.getUserId();
  }

  /// Get all active SOS packets from local storage
  Future<List<SOSPacket>> getActivePackets() async {
    return _packetStore.getActivePackets();
  }

  /// Get unsynced packets for cloud upload
  Future<List<SOSPacket>> getUnsyncedPackets() async {
    return _packetStore.getUnsyncedPackets();
  }

  /// Get broadcast queue size
  int get queueSize => _broadcastQueue.length;

  /// Dispose resources
  void dispose() {
    _eventChannelSubscription?.cancel();
    _eventChannelSubscription = null;
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _connectionStateController.close();
    _packetReceivedController.close();
    _errorController.close();
    _echoController.close();
    _verificationController.close();
    _handshakeController.close();
  }
}
