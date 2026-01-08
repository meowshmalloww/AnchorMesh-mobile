/// Connectivity Service
/// Monitors network connectivity and determines best communication path

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Network type
enum NetworkType {
  none,
  wifi,
  mobile,
  ethernet,
  bluetooth,
  vpn,
  other;

  bool get hasInternet =>
      this != NetworkType.none && this != NetworkType.bluetooth;
}

/// Network quality estimation
enum NetworkQuality {
  none,
  poor,
  fair,
  good,
  excellent;

  bool get isUsable => this != NetworkQuality.none && this != NetworkQuality.poor;
}

/// Current connectivity state
class ConnectivityState {
  final NetworkType networkType;
  final NetworkQuality quality;
  final bool hasInternet;
  final DateTime timestamp;

  ConnectivityState({
    this.networkType = NetworkType.none,
    this.quality = NetworkQuality.none,
    this.hasInternet = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Should use direct API call
  bool get shouldUseDirectApi => hasInternet && quality.isUsable;

  /// Should use mesh networking
  bool get shouldUseMesh => !hasInternet || !quality.isUsable;

  ConnectivityState copyWith({
    NetworkType? networkType,
    NetworkQuality? quality,
    bool? hasInternet,
  }) {
    return ConnectivityState(
      networkType: networkType ?? this.networkType,
      quality: quality ?? this.quality,
      hasInternet: hasInternet ?? this.hasInternet,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() =>
      'ConnectivityState(type: $networkType, quality: $quality, internet: $hasInternet)';
}

/// Connectivity service for monitoring network state
class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity;

  StreamSubscription<ConnectivityResult>? _subscription;
  ConnectivityState _currentState = ConnectivityState();
  Timer? _qualityCheckTimer;

  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  /// Current connectivity state
  ConnectivityState get currentState => _currentState;

  /// Stream of connectivity state changes
  Stream<ConnectivityState> get stateStream => _stateController.stream;
  final _stateController = StreamController<ConnectivityState>.broadcast();

  /// Whether device has internet
  bool get hasInternet => _currentState.hasInternet;

  /// Initialize the service
  Future<void> initialize() async {
    // Get initial state
    final result = await _connectivity.checkConnectivity();
    _updateState(result);

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen(_updateState);

    // Periodically check quality
    _qualityCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkNetworkQuality(),
    );
  }

  /// Update state based on connectivity result
  void _updateState(ConnectivityResult result) {
    final networkType = _mapToNetworkType(result);
    final hasInternet = networkType.hasInternet;

    _currentState = ConnectivityState(
      networkType: networkType,
      quality: hasInternet ? NetworkQuality.good : NetworkQuality.none,
      hasInternet: hasInternet,
      timestamp: DateTime.now(),
    );

    _stateController.add(_currentState);
    notifyListeners();

    // Check actual quality if we have a connection
    if (hasInternet) {
      _checkNetworkQuality();
    }
  }

  /// Map connectivity result to network type
  NetworkType _mapToNetworkType(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.wifi:
        return NetworkType.wifi;
      case ConnectivityResult.mobile:
        return NetworkType.mobile;
      case ConnectivityResult.ethernet:
        return NetworkType.ethernet;
      case ConnectivityResult.bluetooth:
        return NetworkType.bluetooth;
      case ConnectivityResult.vpn:
        return NetworkType.vpn;
      case ConnectivityResult.none:
        return NetworkType.none;
      default:
        return NetworkType.other;
    }
  }

  /// Check network quality by measuring latency
  Future<void> _checkNetworkQuality() async {
    if (!_currentState.hasInternet) return;

    try {
      final stopwatch = Stopwatch()..start();

      // Simple connectivity check - in production, ping your server
      await Future.delayed(const Duration(milliseconds: 100));

      stopwatch.stop();
      final latency = stopwatch.elapsedMilliseconds;

      NetworkQuality quality;
      if (latency < 100) {
        quality = NetworkQuality.excellent;
      } else if (latency < 300) {
        quality = NetworkQuality.good;
      } else if (latency < 1000) {
        quality = NetworkQuality.fair;
      } else {
        quality = NetworkQuality.poor;
      }

      if (quality != _currentState.quality) {
        _currentState = _currentState.copyWith(quality: quality);
        _stateController.add(_currentState);
        notifyListeners();
      }
    } catch (e) {
      // Network check failed, assume poor quality
      _currentState = _currentState.copyWith(
        quality: NetworkQuality.poor,
        hasInternet: false,
      );
      _stateController.add(_currentState);
      notifyListeners();
    }
  }

  /// Force refresh connectivity state
  Future<void> refresh() async {
    final result = await _connectivity.checkConnectivity();
    _updateState(result);
  }

  /// Dispose resources
  @override
  void dispose() {
    _subscription?.cancel();
    _qualityCheckTimer?.cancel();
    _stateController.close();
    super.dispose();
  }
}
