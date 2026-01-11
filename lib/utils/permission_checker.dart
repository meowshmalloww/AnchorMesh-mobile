// Permission Checker Utility
// Provides a centralized system check for all required permissions and states
// Required for mesh networking to function correctly.

import 'dart:io';
import 'package:flutter/services.dart';

/// Represents a system check failure
class SystemCheckFailure {
  final String name;
  final String description;
  final String? suggestion;
  final SystemCheckSeverity severity;

  const SystemCheckFailure({
    required this.name,
    required this.description,
    this.suggestion,
    this.severity = SystemCheckSeverity.error,
  });

  @override
  String toString() {
    return '[$severity] $name: $description${suggestion != null ? ' | Fix: $suggestion' : ''}';
  }
}

enum SystemCheckSeverity { warning, error, critical }

/// Result of all system checks
class SystemCheckResult {
  final List<SystemCheckFailure> failures;
  final DateTime timestamp;

  SystemCheckResult({required this.failures, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  bool get isAllPassed => failures.isEmpty;
  bool get hasErrors =>
      failures.any((f) => f.severity == SystemCheckSeverity.error);
  bool get hasCritical =>
      failures.any((f) => f.severity == SystemCheckSeverity.critical);

  List<SystemCheckFailure> get warnings =>
      failures.where((f) => f.severity == SystemCheckSeverity.warning).toList();
  List<SystemCheckFailure> get errors =>
      failures.where((f) => f.severity == SystemCheckSeverity.error).toList();
  List<SystemCheckFailure> get criticalErrors => failures
      .where((f) => f.severity == SystemCheckSeverity.critical)
      .toList();

  @override
  String toString() {
    if (isAllPassed) {
      return '✅ All system checks passed';
    }
    return '''
⚠️ System Check Results:
  Critical: ${criticalErrors.length}
  Errors: ${errors.length}
  Warnings: ${warnings.length}
  
${failures.map((f) => '  - $f').join('\n')}
''';
  }
}

/// Permission Checker for ResQ Mesh App
/// Checks all required system states and permissions
class PermissionChecker {
  static const MethodChannel _channel = MethodChannel(
    'com.project_flutter/ble',
  );

  /// Check all systems required for mesh networking
  /// Returns a list of failures (empty if all systems are GO)
  static Future<SystemCheckResult> checkAllSystems() async {
    final failures = <SystemCheckFailure>[];

    // 1. Check Bluetooth State
    final bluetoothFailure = await _checkBluetooth();
    if (bluetoothFailure != null) {
      failures.add(bluetoothFailure);
    }

    // 2. Check Location Permission
    final locationFailure = await _checkLocationPermission();
    if (locationFailure != null) {
      failures.add(locationFailure);
    }

    // 3. Check Battery Optimization (Android only)
    if (Platform.isAndroid) {
      final batteryFailure = await _checkBatteryOptimization();
      if (batteryFailure != null) {
        failures.add(batteryFailure);
      }
    }

    // 4. Check BLE Permissions (Android 12+)
    if (Platform.isAndroid) {
      final blePermFailure = await _checkBlePermissions();
      if (blePermFailure != null) {
        failures.add(blePermFailure);
      }
    }

    // 5. Check Background Mode (iOS only)
    if (Platform.isIOS) {
      final backgroundFailure = await _checkIOSBackgroundMode();
      if (backgroundFailure != null) {
        failures.add(backgroundFailure);
      }
    }

    return SystemCheckResult(failures: failures);
  }

  /// Check if Bluetooth is enabled
  static Future<SystemCheckFailure?> _checkBluetooth() async {
    try {
      final state = await _channel.invokeMethod<String>('getBluetoothState');

      if (state == 'off' || state == 'poweredOff') {
        return const SystemCheckFailure(
          name: 'Bluetooth OFF',
          description: 'Bluetooth is disabled',
          suggestion: 'Enable Bluetooth in Settings',
          severity: SystemCheckSeverity.critical,
        );
      }

      if (state == 'unknown' || state == 'unauthorized') {
        return const SystemCheckFailure(
          name: 'Bluetooth Unavailable',
          description: 'Bluetooth is not available or not authorized',
          suggestion:
              'Check device supports Bluetooth and permissions are granted',
          severity: SystemCheckSeverity.critical,
        );
      }

      return null; // Bluetooth is ON
    } on PlatformException catch (e) {
      return SystemCheckFailure(
        name: 'Bluetooth Check Failed',
        description: 'Could not check Bluetooth state: ${e.message}',
        severity: SystemCheckSeverity.error,
      );
    } catch (e) {
      return SystemCheckFailure(
        name: 'Bluetooth Check Error',
        description: 'Unexpected error: $e',
        severity: SystemCheckSeverity.error,
      );
    }
  }

  /// Check if Location Permission is granted
  static Future<SystemCheckFailure?> _checkLocationPermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>(
        'checkLocationPermission',
      );

      if (granted != true) {
        return const SystemCheckFailure(
          name: 'Location Permission Denied',
          description: 'Location access is required for BLE scanning',
          suggestion: 'Grant location permission in app settings',
          severity: SystemCheckSeverity.critical,
        );
      }

      return null; // Permission granted
    } on PlatformException {
      // Method not implemented - assume granted for testing
      return null;
    } catch (e) {
      return SystemCheckFailure(
        name: 'Location Check Failed',
        description: 'Could not check location permission: $e',
        severity: SystemCheckSeverity.warning,
      );
    }
  }

  /// Check if Battery Optimization is ignored (Android only)
  static Future<SystemCheckFailure?> _checkBatteryOptimization() async {
    if (!Platform.isAndroid) return null;

    try {
      final ignored = await _channel.invokeMethod<bool>(
        'isBatteryOptimizationIgnored',
      );

      if (ignored != true) {
        return const SystemCheckFailure(
          name: 'Battery Optimization Active',
          description: 'App may be killed in background to save battery',
          suggestion: 'Disable battery optimization for this app',
          severity: SystemCheckSeverity.warning,
        );
      }

      return null; // Battery optimization is ignored
    } on PlatformException {
      // Method not implemented - return warning
      return const SystemCheckFailure(
        name: 'Battery Optimization Unknown',
        description: 'Could not check battery optimization status',
        suggestion:
            'Manually disable battery optimization for reliable background operation',
        severity: SystemCheckSeverity.warning,
      );
    }
  }

  /// Check BLE permissions (Android 12+)
  static Future<SystemCheckFailure?> _checkBlePermissions() async {
    if (!Platform.isAndroid) return null;

    try {
      final granted = await _channel.invokeMethod<bool>('checkBlePermissions');

      if (granted != true) {
        return const SystemCheckFailure(
          name: 'BLE Permissions Denied',
          description:
              'Bluetooth scan/advertise/connect permissions not granted',
          suggestion: 'Grant nearby devices permission in settings',
          severity: SystemCheckSeverity.critical,
        );
      }

      return null;
    } on PlatformException {
      // Method not implemented - assume granted
      return null;
    }
  }

  /// Check iOS Background Mode configuration
  static Future<SystemCheckFailure?> _checkIOSBackgroundMode() async {
    if (!Platform.isIOS) return null;

    // This would typically check Info.plist configuration
    // For now, return null (assumed configured correctly)
    return null;
  }

  /// Quick check - just returns true/false
  static Future<bool> isSystemReady() async {
    final result = await checkAllSystems();
    return result.isAllPassed || !result.hasCritical;
  }

  /// Get a simple status string
  static Future<String> getStatusSummary() async {
    final result = await checkAllSystems();

    if (result.isAllPassed) {
      return '🟢 All Systems GO';
    } else if (result.hasCritical) {
      return '🔴 Critical Issues (${result.criticalErrors.length})';
    } else if (result.hasErrors) {
      return '🟠 Errors (${result.errors.length})';
    } else {
      return '🟡 Warnings (${result.warnings.length})';
    }
  }
}

/// Convenience function to check all systems
Future<SystemCheckResult> checkAllSystems() =>
    PermissionChecker.checkAllSystems();

/// Convenience function for quick readiness check
Future<bool> isSystemReady() => PermissionChecker.isSystemReady();
