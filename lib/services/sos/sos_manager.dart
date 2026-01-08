// SOS Manager
// Main orchestrator for SOS functionality - coordinates BLE mesh, API, and connectivity

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/sos_alert.dart';
import '../../models/device_info.dart';
import '../../models/peer_device.dart';
import '../ble/ble_mesh_service.dart';
import '../connectivity/connectivity_service.dart';
import '../api/api_service.dart';
import '../crypto/encryption_service.dart';

/// SOS state
enum SosState {
  idle,
  initiating,
  broadcasting,
  delivered,
  acknowledged,
  cancelled,
  error;

  bool get isActive =>
      this == SosState.initiating ||
      this == SosState.broadcasting ||
      this == SosState.delivered;
}

/// SOS Manager state
class SOSManagerState {
  final SosState sosState;
  final SOSAlert? activeAlert;
  final int peersReached;
  final bool serverReached;
  final String? errorMessage;

  const SOSManagerState({
    this.sosState = SosState.idle,
    this.activeAlert,
    this.peersReached = 0,
    this.serverReached = false,
    this.errorMessage,
  });

  bool get isActive => sosState.isActive;
  bool get hasError => sosState == SosState.error;

  SOSManagerState copyWith({
    SosState? sosState,
    SOSAlert? activeAlert,
    int? peersReached,
    bool? serverReached,
    String? errorMessage,
  }) {
    return SOSManagerState(
      sosState: sosState ?? this.sosState,
      activeAlert: activeAlert ?? this.activeAlert,
      peersReached: peersReached ?? this.peersReached,
      serverReached: serverReached ?? this.serverReached,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// SOS Manager configuration
class SOSManagerConfig {
  final bool autoRelay;
  final bool notifyIncoming;
  final double maxAlertDistanceMeters;
  final bool persistUntilServerConfirm;
  final bool updateLocationOnSos;
  final Duration heartbeatInterval;
  final String serverBaseUrl;

  const SOSManagerConfig({
    this.autoRelay = true,
    this.notifyIncoming = true,
    this.maxAlertDistanceMeters = 10000,
    this.persistUntilServerConfirm = true,
    this.updateLocationOnSos = true,
    this.heartbeatInterval = const Duration(minutes: 5),
    this.serverBaseUrl = 'http://localhost:3000',
  });
}

/// Main SOS Manager - orchestrates all services
class SOSManager extends ChangeNotifier {
  final SOSManagerConfig config;

  // Services
  late final BLEMeshService _bleMeshService;
  late final ConnectivityService _connectivityService;
  late final ApiService _apiService;
  late final EncryptionService _encryptionService;
  late final LocalDevice _localDevice;

  // State
  SOSManagerState _state = const SOSManagerState();
  bool _isInitialized = false;

  // Received alerts
  final Map<String, SOSAlert> _receivedAlerts = {};

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];
  Timer? _heartbeatTimer;

  SOSManager({this.config = const SOSManagerConfig()});

  /// Current state
  SOSManagerState get state => _state;

  /// Whether manager is initialized
  bool get isInitialized => _isInitialized;

  /// Active SOS alert
  SOSAlert? get activeAlert => _state.activeAlert;

  /// Received SOS alerts from others
  List<SOSAlert> get receivedAlerts => _receivedAlerts.values.toList();

  /// BLE mesh service (for UI display)
  BLEMeshService get bleMeshService => _bleMeshService;

  /// Connectivity service (for UI display)
  ConnectivityService get connectivityService => _connectivityService;

  /// Initialize all services
  Future<bool> initialize(LocalDevice device) async {
    if (_isInitialized) return true;

    _localDevice = device;

    // Initialize encryption
    _encryptionService = EncryptionService();
    await _encryptionService.initialize();

    // Initialize connectivity
    _connectivityService = ConnectivityService();
    await _connectivityService.initialize();

    // Initialize API service
    _apiService = ApiService(
      config: ApiConfig(baseUrl: config.serverBaseUrl),
      localDevice: _localDevice,
    );

    // Register with server if online
    if (_connectivityService.hasInternet) {
      final result = await _apiService.registerDevice();
      if (result.success && result.data != null) {
        _localDevice.authToken = result.data!.token;
        await _encryptionService.setAppSignature(result.data!.appSignature);
        await _apiService.connectWebSocket();
      }
    }

    // Initialize BLE mesh
    _bleMeshService = BLEMeshService(
      encryptionService: _encryptionService,
      localDevice: _localDevice,
    );
    await _bleMeshService.initialize();

    // Setup event listeners
    _setupEventListeners();

    // Start heartbeat
    _heartbeatTimer = Timer.periodic(config.heartbeatInterval, (_) {
      _sendHeartbeat();
    });

    _isInitialized = true;
    notifyListeners();

    return true;
  }

  /// Setup event listeners for all services
  void _setupEventListeners() {
    // Listen to connectivity changes
    _subscriptions.add(
      _connectivityService.stateStream.listen(_handleConnectivityChange),
    );

    // Listen to BLE mesh events
    _subscriptions.add(
      _bleMeshService.events.listen(_handleBleMeshEvent),
    );

    // Listen to server events
    _subscriptions.add(
      _apiService.serverEvents.listen(_handleServerEvent),
    );
  }

  /// Handle connectivity changes
  void _handleConnectivityChange(ConnectivityState connectivity) async {
    if (connectivity.hasInternet) {
      // Flush pending messages
      await _apiService.flushPendingMessages();

      // Connect WebSocket
      if (!_apiService.isWsConnected) {
        await _apiService.connectWebSocket();
      }

      // Send active SOS if not yet delivered to server
      if (_state.activeAlert != null && !_state.serverReached) {
        final result = await _apiService.sendSosAlert(_state.activeAlert!);
        if (result.success) {
          _updateState(_state.copyWith(
            serverReached: true,
            sosState: SosState.delivered,
          ));
        }
      }

      // Send relayed alerts
      for (final alert in _receivedAlerts.values) {
        if (!alert.deliveredToServer) {
          final result = await _apiService.sendRelayedSos(alert);
          if (result.success) {
            alert.deliveredToServer = true;
          }
        }
      }
    }
  }

  /// Handle BLE mesh events
  void _handleBleMeshEvent(BleMeshEvent event) {
    if (event is MessageReceivedEvent) {
      _handleIncomingAlert(event.message, event.fromPeer);
    } else if (event is MessageRelayedEvent) {
      _updateState(_state.copyWith(
        peersReached: _state.peersReached + 1,
      ));
    } else if (event is AcknowledgmentReceivedEvent) {
      if (event.deliveredToServer &&
          _state.activeAlert?.messageId == event.originalMessageId) {
        _updateState(_state.copyWith(
          serverReached: true,
          sosState: SosState.delivered,
        ));
      }
    } else if (event is BleErrorEvent) {
      // Log error but don't fail
    }
  }

  /// Handle incoming SOS alert from mesh
  void _handleIncomingAlert(SOSAlert alert, PeerDevice fromPeer) {
    // Skip if already have this alert
    if (_receivedAlerts.containsKey(alert.messageId)) return;

    // Skip if this is our own alert
    if (alert.originatorDeviceId == _localDevice.deviceId) return;

    // Store the alert
    _receivedAlerts[alert.messageId] = alert;
    notifyListeners();

    // Auto-relay if configured
    if (config.autoRelay && !alert.isExpired) {
      // BLE mesh handles relay automatically
    }

    // Send to server if we have internet
    if (_connectivityService.hasInternet) {
      _apiService.sendRelayedSos(alert).then((result) {
        if (result.success) {
          alert.deliveredToServer = true;
          notifyListeners();
        }
      });
    }
  }

  /// Handle server events
  void _handleServerEvent(ServerEvent event) {
    if (event is SosAcknowledgedEvent) {
      if (_state.activeAlert?.messageId == event.messageId) {
        _updateState(_state.copyWith(
          serverReached: true,
          sosState: SosState.acknowledged,
        ));
      }
    }
  }

  /// Initiate an SOS alert
  Future<SOSAlert?> initiateSOS({
    required EmergencyType emergencyType,
    String? message,
    MessagePriority priority = MessagePriority.critical,
    GeoLocation? location,
  }) async {
    if (_state.isActive) {
      _updateState(_state.copyWith(
        errorMessage: 'SOS already active',
      ));
      return null;
    }

    _updateState(_state.copyWith(sosState: SosState.initiating));

    // Get location
    GeoLocation finalLocation;
    if (location != null) {
      finalLocation = location;
    } else if (config.updateLocationOnSos) {
      try {
        finalLocation = await _getCurrentLocation();
        _localDevice.lastKnownLocation = finalLocation;
      } catch (e) {
        if (_localDevice.lastKnownLocation != null) {
          finalLocation = _localDevice.lastKnownLocation!;
        } else {
          _updateState(_state.copyWith(
            sosState: SosState.error,
            errorMessage: 'Could not get location: $e',
          ));
          return null;
        }
      }
    } else if (_localDevice.lastKnownLocation != null) {
      finalLocation = _localDevice.lastKnownLocation!;
    } else {
      _updateState(_state.copyWith(
        sosState: SosState.error,
        errorMessage: 'No location available',
      ));
      return null;
    }

    // Create SOS alert
    final alert = SOSAlert(
      messageId: _encryptionService.generateMessageId(),
      originatorDeviceId: _localDevice.deviceId,
      appSignature: _encryptionService.appSignature,
      emergencyType: emergencyType,
      priority: priority,
      location: finalLocation,
      message: message,
    );

    // Sign the message
    final signature = _encryptionService.signMessage(alert);

    // Create signed alert
    final signedAlert = SOSAlert(
      messageId: alert.messageId,
      originatorDeviceId: alert.originatorDeviceId,
      appSignature: alert.appSignature,
      emergencyType: alert.emergencyType,
      priority: alert.priority,
      location: alert.location,
      message: alert.message,
      signature: signature,
      originatedAt: alert.originatedAt,
      expiresAt: alert.expiresAt,
    );

    _updateState(_state.copyWith(
      sosState: SosState.broadcasting,
      activeAlert: signedAlert,
      peersReached: 0,
      serverReached: false,
    ));

    // Check connectivity and send
    if (_connectivityService.hasInternet &&
        _connectivityService.currentState.shouldUseDirectApi) {
      // Send directly to server
      final result = await _apiService.sendSosAlert(signedAlert);
      if (result.success) {
        _updateState(_state.copyWith(
          serverReached: true,
          sosState: SosState.delivered,
        ));
      }
    }

    // Always broadcast to mesh for nearby alerts
    await _bleMeshService.broadcastSOS(signedAlert);

    return signedAlert;
  }

  /// Cancel active SOS
  Future<void> cancelSOS() async {
    if (_state.activeAlert == null) return;

    final messageId = _state.activeAlert!.messageId;

    // Stop mesh broadcasting
    _bleMeshService.stopSOS(messageId);

    // Notify server if connected
    if (_connectivityService.hasInternet) {
      await _apiService.cancelSos(messageId);
    }

    _updateState(const SOSManagerState(sosState: SosState.cancelled));
  }

  /// Get current location
  Future<GeoLocation> _getCurrentLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions permanently denied');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );

    return GeoLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      accuracy: position.accuracy,
      timestamp: DateTime.now(),
    );
  }

  /// Update state and notify
  void _updateState(SOSManagerState newState) {
    _state = newState;
    notifyListeners();
  }

  /// Send heartbeat
  void _sendHeartbeat() async {
    if (_connectivityService.hasInternet) {
      await _apiService.heartbeat();
    }
  }

  /// Update location periodically
  Future<void> updateLocation() async {
    try {
      final location = await _getCurrentLocation();
      _localDevice.lastKnownLocation = location;

      if (_connectivityService.hasInternet) {
        await _apiService.updateLocation(location);
      }
    } catch (_) {}
  }

  /// Clear received alerts
  void clearReceivedAlerts() {
    _receivedAlerts.clear();
    notifyListeners();
  }

  /// Dismiss a specific received alert
  void dismissReceivedAlert(String messageId) {
    _receivedAlerts.remove(messageId);
    notifyListeners();
  }

  /// Get full status
  Map<String, dynamic> getStatus() {
    return {
      'isInitialized': _isInitialized,
      'state': _state.sosState.name,
      'hasActiveAlert': _state.activeAlert != null,
      'peersReached': _state.peersReached,
      'serverReached': _state.serverReached,
      'connectivity': {
        'hasInternet': _connectivityService.hasInternet,
        'type': _connectivityService.currentState.networkType.name,
        'quality': _connectivityService.currentState.quality.name,
      },
      'mesh': _bleMeshService.getStatus(),
      'receivedAlerts': _receivedAlerts.length,
    };
  }

  /// Dispose resources
  @override
  void dispose() {
    _heartbeatTimer?.cancel();

    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    _bleMeshService.dispose();
    _connectivityService.dispose();
    _apiService.dispose();

    super.dispose();
  }
}
