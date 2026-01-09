import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'connectivity_service.dart';

/// Platform-specific service for iOS/Android features
/// Handles: Low Power Mode, Screen Always-On, Auto-Activate, Background scanning
class PlatformService {
  static const _channel = MethodChannel('com.project_flutter/platform');

  static PlatformService? _instance;

  static PlatformService get instance {
    _instance ??= PlatformService._();
    return _instance!;
  }

  PlatformService._() {
    _init();
  }

  // State
  bool _isLowPowerModeEnabled = false;
  bool _isScreenAlwaysOn = false;
  bool _isAutoActivateEnabled = true;
  bool _isMeshAutoActivated = false;
  int _consecutivePingFailures = 0;
  Timer? _pingTimer;

  // Streams
  final _lowPowerModeController = StreamController<bool>.broadcast();
  final _autoActivateController = StreamController<bool>.broadcast();

  /// Stream of low power mode changes
  Stream<bool> get lowPowerModeStream => _lowPowerModeController.stream;

  /// Stream of auto-activate events
  Stream<bool> get autoActivateStream => _autoActivateController.stream;

  /// Whether device is in low power mode
  bool get isLowPowerModeEnabled => _isLowPowerModeEnabled;

  /// Whether screen is set to always on
  bool get isScreenAlwaysOn => _isScreenAlwaysOn;

  /// Whether mesh was auto-activated due to failed pings
  bool get isMeshAutoActivated => _isMeshAutoActivated;

  void _init() {
    // Listen for native platform events
    _channel.setMethodCallHandler(_handleMethodCall);

    // Check initial low power mode state
    _checkLowPowerMode();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onLowPowerModeChanged':
        final enabled = call.arguments as bool? ?? false;
        _isLowPowerModeEnabled = enabled;
        _lowPowerModeController.add(enabled);
        debugPrint('Low Power Mode changed: $enabled');
        break;
      case 'onAppStateChanged':
        final state = call.arguments as String?;
        _handleAppStateChange(state);
        break;
    }
  }

  void _handleAppStateChange(String? state) {
    if (state == 'foreground') {
      // App came to foreground - check if we need to warn about low power mode
      if (_isLowPowerModeEnabled) {
        // Should show warning in UI
      }
    }
  }

  // ==================
  // Low Power Mode (iOS)
  // ==================

  /// Check if device is in Low Power Mode (iOS)
  Future<bool> _checkLowPowerMode() async {
    if (!Platform.isIOS) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('isLowPowerModeEnabled');
      _isLowPowerModeEnabled = result ?? false;
      return _isLowPowerModeEnabled;
    } on PlatformException catch (e) {
      debugPrint('Failed to check low power mode: ${e.message}');
      return false;
    }
  }

  /// Check if device is in Low Power Mode
  Future<bool> checkLowPowerMode() async {
    return _checkLowPowerMode();
  }

  // ==================
  // Screen Always-On (iOS: isIdleTimerDisabled)
  // ==================

  /// Set screen to stay on (prevents auto-lock)
  /// iOS: Sets UIApplication.shared.isIdleTimerDisabled = true
  /// Android: Uses FLAG_KEEP_SCREEN_ON
  Future<bool> setScreenAlwaysOn(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<bool>('setScreenAlwaysOn', {
        'enabled': enabled,
      });
      _isScreenAlwaysOn = result ?? false;
      debugPrint('Screen always on: $_isScreenAlwaysOn');
      return _isScreenAlwaysOn;
    } on PlatformException catch (e) {
      debugPrint('Failed to set screen always on: ${e.message}');
      return false;
    }
  }

  /// Enable screen always-on when SOS is active
  Future<void> enableSOSMode() async {
    await setScreenAlwaysOn(true);
  }

  /// Disable screen always-on when SOS is stopped
  Future<void> disableSOSMode() async {
    await setScreenAlwaysOn(false);
  }

  // ==================
  // Auto-Activate Mesh on Failed Pings
  // ==================

  /// Start monitoring internet connectivity
  /// Auto-activates mesh after 3 consecutive failed pings
  void startAutoActivateMonitoring() {
    stopAutoActivateMonitoring();

    _consecutivePingFailures = 0;
    _isMeshAutoActivated = false;

    // Check every 30 seconds
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _checkConnectivityAndActivate();
    });

    // Check immediately
    _checkConnectivityAndActivate();

    debugPrint('Auto-activate monitoring started');
  }

  /// Stop monitoring
  void stopAutoActivateMonitoring() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  Future<void> _checkConnectivityAndActivate() async {
    if (!_isAutoActivateEnabled) return;

    final hasInternet = await ConnectivityChecker.instance.checkInternet();

    if (hasInternet) {
      _consecutivePingFailures = 0;

      // If mesh was auto-activated and internet is back, could auto-deactivate
      if (_isMeshAutoActivated) {
        debugPrint('Internet restored - mesh was auto-activated');
        // Don't auto-deactivate, let user decide
      }
    } else {
      _consecutivePingFailures++;
      debugPrint('Ping failed: $_consecutivePingFailures consecutive failures');

      if (_consecutivePingFailures >= 3 && !_isMeshAutoActivated) {
        _activateMeshAutomatically();
      }
    }
  }

  void _activateMeshAutomatically() {
    _isMeshAutoActivated = true;
    _autoActivateController.add(true);
    debugPrint('Auto-activating mesh due to 3 consecutive ping failures!');

    // Note: Actual mesh activation should be handled by the UI
    // since we need location and user consent
  }

  /// Enable/disable auto-activation feature
  void setAutoActivateEnabled(bool enabled) {
    _isAutoActivateEnabled = enabled;
  }

  /// Reset auto-activation state
  void resetAutoActivation() {
    _consecutivePingFailures = 0;
    _isMeshAutoActivated = false;
  }

  // ==================
  // Background UUID Scanning (iOS)
  // ==================

  /// Request background scanning for specific service UUID
  /// iOS: Registers UUID for background wake-up
  Future<bool> registerBackgroundScanning(String serviceUUID) async {
    if (!Platform.isIOS) {
      // Android uses foreground service instead
      return true;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'registerBackgroundScan',
        {'serviceUUID': serviceUUID},
      );
      debugPrint('Background scanning registered: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to register background scanning: ${e.message}');
      return false;
    }
  }

  // ==================
  // State Preservation (iOS)
  // ==================

  /// Save state for restoration after app termination
  Future<void> saveStateForRestoration({
    required bool isBroadcasting,
    required bool isScanning,
    double? latitude,
    double? longitude,
    int? status,
  }) async {
    try {
      await _channel.invokeMethod('saveStateForRestoration', {
        'isBroadcasting': isBroadcasting,
        'isScanning': isScanning,
        'latitude': latitude,
        'longitude': longitude,
        'status': status,
      });
      debugPrint('State saved for restoration');
    } on PlatformException catch (e) {
      debugPrint('Failed to save state: ${e.message}');
    }
  }

  /// Restore state after app relaunch
  Future<Map<String, dynamic>?> restoreState() async {
    try {
      final result = await _channel.invokeMethod<Map>('restoreState');
      if (result != null) {
        debugPrint('State restored: $result');
        return result.cast<String, dynamic>();
      }
    } on PlatformException catch (e) {
      debugPrint('Failed to restore state: ${e.message}');
    }
    return null;
  }

  // ==================
  // Request Battery Optimization Exemption (Android)
  // ==================

  /// Request to ignore battery optimization (Android only)
  Future<bool> requestIgnoreBatteryOptimization() async {
    if (!Platform.isAndroid) {
      return true; // Not needed on iOS
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'requestIgnoreBatteryOptimization',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint(
        'Failed to request battery optimization exemption: ${e.message}',
      );
      return false;
    }
  }

  /// Check if app is exempt from battery optimization
  Future<bool> isIgnoringBatteryOptimization() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimization',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to check battery optimization: ${e.message}');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    stopAutoActivateMonitoring();
    _lowPowerModeController.close();
    _autoActivateController.close();
  }
}
