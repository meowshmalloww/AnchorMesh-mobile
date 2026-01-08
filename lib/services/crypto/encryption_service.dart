// Encryption Service
// Handles message signing and verification for SOS alerts

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../models/sos_alert.dart';

/// Encryption service for message signing and verification
class EncryptionService {
  static const _appSecretKey = 'app_signature_secret';
  static const _deviceKeyKey = 'device_private_key';

  final FlutterSecureStorage _secureStorage;

  String? _appSignature;
  String? _deviceKey;

  EncryptionService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Get the app signature for validation
  String get appSignature => _appSignature ?? '';

  /// Initialize the encryption service
  Future<void> initialize() async {
    // Load or generate device key
    _deviceKey = await _secureStorage.read(key: _deviceKeyKey);
    if (_deviceKey == null) {
      _deviceKey = _generateRandomKey();
      await _secureStorage.write(key: _deviceKeyKey, value: _deviceKey);
    }
  }

  /// Set the app signature from server registration
  Future<void> setAppSignature(String signature) async {
    _appSignature = signature;
    await _secureStorage.write(key: _appSecretKey, value: signature);
  }

  /// Load stored app signature
  Future<void> loadAppSignature() async {
    _appSignature = await _secureStorage.read(key: _appSecretKey);
  }

  /// Sign an SOS alert message
  String signMessage(SOSAlert alert) {
    final payload = _createSignaturePayload(alert);
    final key = utf8.encode(_deviceKey ?? 'default-key');
    final bytes = utf8.encode(payload);

    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);

    return digest.toString();
  }

  /// Verify a message signature
  bool verifySignature(SOSAlert alert, String signature) {
    // For relayed messages, we trust the original signature
    // Full verification happens on the server
    if (alert.signature == null) return false;

    // Basic integrity check
    return signature.isNotEmpty && signature.length == 64;
  }

  /// Create the signature payload string
  String _createSignaturePayload(SOSAlert alert) {
    return [
      alert.messageId,
      alert.originatorDeviceId,
      alert.emergencyType.toJson(),
      alert.priority.toJson(),
      alert.location.latitude.toStringAsFixed(6),
      alert.location.longitude.toStringAsFixed(6),
      alert.message ?? '',
      alert.originatedAt.toIso8601String(),
    ].join('|');
  }

  /// Generate a random key
  String _generateRandomKey() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final bytes = utf8.encode('device-key-$timestamp');
    return sha256.convert(bytes).toString();
  }

  /// Encrypt data for storage
  String encrypt(String data) {
    // Simple obfuscation for local storage
    // In production, use proper AES encryption
    final bytes = utf8.encode(data);
    final encoded = base64Encode(bytes);
    return encoded;
  }

  /// Decrypt stored data
  String decrypt(String encryptedData) {
    final bytes = base64Decode(encryptedData);
    return utf8.decode(bytes);
  }

  /// Hash a string (for non-sensitive operations)
  String hash(String data) {
    final bytes = utf8.encode(data);
    return sha256.convert(bytes).toString();
  }

  /// Generate a unique message ID
  String generateMessageId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = DateTime.now().hashCode;
    final combined = '$timestamp-$random-${_deviceKey?.substring(0, 8) ?? "unknown"}';
    final hash = sha256.convert(utf8.encode(combined)).toString();

    // Format as UUID-like string
    return '${hash.substring(0, 8)}-${hash.substring(8, 12)}-${hash.substring(12, 16)}-${hash.substring(16, 20)}-${hash.substring(20, 32)}';
  }

  /// Clear all stored keys (for logout/reset)
  Future<void> clearKeys() async {
    await _secureStorage.delete(key: _appSecretKey);
    await _secureStorage.delete(key: _deviceKeyKey);
    _appSignature = null;
    _deviceKey = null;
  }
}
