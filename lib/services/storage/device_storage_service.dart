// Device Storage Service
// Handles persistent storage for device ID, server URL, and other settings

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Keys for secure storage
class StorageKeys {
  static const String deviceId = 'device_id';
  static const String serverUrl = 'server_url';
  static const String authToken = 'auth_token';
  static const String appSignature = 'app_signature';
}

/// Device Storage Service - singleton for managing persistent storage
class DeviceStorageService {
  static final DeviceStorageService _instance = DeviceStorageService._internal();
  factory DeviceStorageService() => _instance;
  DeviceStorageService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  String? _cachedDeviceId;
  String? _cachedServerUrl;

  /// Default server URL (can be overridden in settings)
  static const String defaultServerUrl = 'https://sos-relay.example.com';

  /// Initialize the storage service and ensure device ID exists
  Future<void> initialize() async {
    _cachedDeviceId = await getDeviceId();
    _cachedServerUrl = await getServerUrl();
  }

  /// Get or create a persistent device ID
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    String? deviceId = await _storage.read(key: StorageKeys.deviceId);

    if (deviceId == null || deviceId.isEmpty) {
      // Generate a new UUID-based device ID
      deviceId = const Uuid().v4();
      await _storage.write(key: StorageKeys.deviceId, value: deviceId);
    }

    _cachedDeviceId = deviceId;
    return deviceId;
  }

  /// Get the configured server URL
  Future<String> getServerUrl() async {
    if (_cachedServerUrl != null) return _cachedServerUrl!;

    String? serverUrl = await _storage.read(key: StorageKeys.serverUrl);
    _cachedServerUrl = serverUrl ?? defaultServerUrl;
    return _cachedServerUrl!;
  }

  /// Set the server URL
  Future<void> setServerUrl(String url) async {
    await _storage.write(key: StorageKeys.serverUrl, value: url);
    _cachedServerUrl = url;
  }

  /// Save authentication token
  Future<void> saveAuthToken(String token) async {
    await _storage.write(key: StorageKeys.authToken, value: token);
  }

  /// Get authentication token
  Future<String?> getAuthToken() async {
    return await _storage.read(key: StorageKeys.authToken);
  }

  /// Save app signature
  Future<void> saveAppSignature(String signature) async {
    await _storage.write(key: StorageKeys.appSignature, value: signature);
  }

  /// Get app signature
  Future<String?> getAppSignature() async {
    return await _storage.read(key: StorageKeys.appSignature);
  }

  /// Clear all stored data (for reset)
  Future<void> clearAll() async {
    await _storage.deleteAll();
    _cachedDeviceId = null;
    _cachedServerUrl = null;
  }

  /// Clear authentication data only
  Future<void> clearAuth() async {
    await _storage.delete(key: StorageKeys.authToken);
    await _storage.delete(key: StorageKeys.appSignature);
  }
}
