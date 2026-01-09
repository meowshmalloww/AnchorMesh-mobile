import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Detects OS versions for feature gating and legacy compatibility.
///
/// This service provides version detection for:
/// - iOS 26+ Liquid Glass support
/// - Android 12+ Material You support
/// - Legacy device fallback requirements
///
/// Usage:
/// ```dart
/// final detector = VersionDetector.instance;
/// await detector.initialize();
///
/// if (await detector.supportsLiquidGlass()) {
///   // Use native iOS 26 Liquid Glass
/// } else {
///   // Use BackdropFilter fallback
/// }
/// ```
class VersionDetector {
  static VersionDetector? _instance;

  static VersionDetector get instance {
    _instance ??= VersionDetector._();
    return _instance!;
  }

  VersionDetector._();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Cached values
  bool _isInitialized = false;
  int _iosMajorVersion = 0;
  int _iosMinorVersion = 0;
  int _androidSdkVersion = 0;
  String _deviceModel = '';
  bool _isPhysicalDevice = true;

  /// Whether the detector has been initialized
  bool get isInitialized => _isInitialized;

  /// iOS major version (e.g., 26 for iOS 26.0)
  int get iosMajorVersion => _iosMajorVersion;

  /// iOS minor version (e.g., 0 for iOS 26.0)
  int get iosMinorVersion => _iosMinorVersion;

  /// Android SDK version (e.g., 31 for Android 12)
  int get androidSdkVersion => _androidSdkVersion;

  /// Device model name
  String get deviceModel => _deviceModel;

  /// Whether running on a physical device (not simulator/emulator)
  bool get isPhysicalDevice => _isPhysicalDevice;

  /// Initialize version detection (call once at app startup)
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (Platform.isIOS) {
        await _initializeIOS();
      } else if (Platform.isAndroid) {
        await _initializeAndroid();
      }
      _isInitialized = true;
      debugPrint('VersionDetector: Initialized - '
          'iOS=$_iosMajorVersion.$_iosMinorVersion, '
          'Android SDK=$_androidSdkVersion, '
          'Model=$_deviceModel');
    } catch (e) {
      debugPrint('VersionDetector: Initialization failed: $e');
      _isInitialized = true; // Mark as initialized to prevent retries
    }
  }

  Future<void> _initializeIOS() async {
    final iosInfo = await _deviceInfo.iosInfo;
    _deviceModel = iosInfo.utsname.machine;
    _isPhysicalDevice = iosInfo.isPhysicalDevice;

    // Parse version string (e.g., "26.0" or "15.7.1")
    final versionParts = iosInfo.systemVersion.split('.');
    if (versionParts.isNotEmpty) {
      _iosMajorVersion = int.tryParse(versionParts[0]) ?? 0;
    }
    if (versionParts.length > 1) {
      _iosMinorVersion = int.tryParse(versionParts[1]) ?? 0;
    }
  }

  Future<void> _initializeAndroid() async {
    final androidInfo = await _deviceInfo.androidInfo;
    _androidSdkVersion = androidInfo.version.sdkInt;
    _deviceModel = androidInfo.model;
    _isPhysicalDevice = androidInfo.isPhysicalDevice;
  }

  // ==================
  // iOS Version Checks
  // ==================

  /// Get iOS major version asynchronously (initializes if needed)
  Future<int> getIOSMajorVersion() async {
    if (!_isInitialized) await initialize();
    if (!Platform.isIOS) return 0;
    return _iosMajorVersion;
  }

  /// Check if iOS version is at least the specified version
  Future<bool> isIOSVersionAtLeast(int major, [int minor = 0]) async {
    if (!Platform.isIOS) return false;
    if (!_isInitialized) await initialize();

    if (_iosMajorVersion > major) return true;
    if (_iosMajorVersion == major && _iosMinorVersion >= minor) return true;
    return false;
  }

  /// Check if iOS 26+ Liquid Glass is supported
  ///
  /// Liquid Glass is Apple's translucent design material introduced in iOS 26.
  /// Returns true only on iOS 26.0 or later.
  Future<bool> supportsLiquidGlass() async {
    return await isIOSVersionAtLeast(26);
  }

  /// Check if iOS 15+ modern appearance APIs are supported
  Future<bool> supportsModernAppearance() async {
    return await isIOSVersionAtLeast(15);
  }

  // ==================
  // Android Version Checks
  // ==================

  /// Get Android SDK version asynchronously (initializes if needed)
  Future<int> getAndroidSDKVersion() async {
    if (!_isInitialized) await initialize();
    if (!Platform.isAndroid) return 0;
    return _androidSdkVersion;
  }

  /// Check if Android SDK is at least the specified version
  Future<bool> isAndroidSDKAtLeast(int sdkVersion) async {
    if (!Platform.isAndroid) return false;
    if (!_isInitialized) await initialize();
    return _androidSdkVersion >= sdkVersion;
  }

  /// Check if Android 12+ Material You is supported
  ///
  /// Material You dynamic theming was introduced in Android 12 (SDK 31).
  Future<bool> supportsMaterialYou() async {
    return await isAndroidSDKAtLeast(31); // Android 12 = SDK 31
  }

  /// Check if Android 13+ enhanced permissions are required
  Future<bool> requiresNotificationPermission() async {
    return await isAndroidSDKAtLeast(33); // Android 13 = SDK 33
  }

  // ==================
  // Cross-Platform Checks
  // ==================

  /// Check if native theming effects are supported on this device
  ///
  /// Returns true if either:
  /// - iOS 26+ (Liquid Glass)
  /// - Android 12+ (Material You)
  Future<bool> supportsNativeTheming() async {
    if (Platform.isIOS) {
      return await supportsLiquidGlass();
    } else if (Platform.isAndroid) {
      return await supportsMaterialYou();
    }
    return false;
  }

  /// Check if blur effects are well-supported on this device
  ///
  /// Blur effects have good performance on:
  /// - iOS 13+
  /// - Android 10+ (SDK 29+)
  Future<bool> supportsBlurEffects() async {
    if (Platform.isIOS) {
      return await isIOSVersionAtLeast(13);
    } else if (Platform.isAndroid) {
      return await isAndroidSDKAtLeast(29);
    }
    return false;
  }

  /// Get a summary of device capabilities for debugging
  Future<Map<String, dynamic>> getCapabilitiesSummary() async {
    if (!_isInitialized) await initialize();

    return {
      'platform': Platform.isIOS ? 'iOS' : 'Android',
      'iosVersion': Platform.isIOS ? '$_iosMajorVersion.$_iosMinorVersion' : null,
      'androidSdk': Platform.isAndroid ? _androidSdkVersion : null,
      'model': _deviceModel,
      'isPhysicalDevice': _isPhysicalDevice,
      'supportsLiquidGlass': Platform.isIOS ? await supportsLiquidGlass() : false,
      'supportsMaterialYou': Platform.isAndroid ? await supportsMaterialYou() : false,
      'supportsBlurEffects': await supportsBlurEffects(),
      'supportsNativeTheming': await supportsNativeTheming(),
    };
  }
}

/// SDK version constants for Android
class AndroidSDK {
  static const int android10 = 29; // Q
  static const int android11 = 30; // R
  static const int android12 = 31; // S
  static const int android12L = 32; // S_V2
  static const int android13 = 33; // Tiramisu
  static const int android14 = 34; // Upside Down Cake
  static const int android15 = 35; // Vanilla Ice Cream

  AndroidSDK._();
}
