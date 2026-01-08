import 'dart:math';
import 'sos_status.dart';

/// SOS Packet - The message transmitted via BLE mesh
///
/// Packet Structure (21 bytes):
/// | Byte | Field     | Size | Notes |
/// |------|-----------|------|-------|
/// | 0-1  | Header    | 2B   | 0xFFFF (app identifier) |
/// | 2-5  | User ID   | 4B   | Random, stored in prefs |
/// | 6-7  | Sequence  | 2B   | Increments on location change |
/// | 8-11 | Latitude  | 4B   | ×10^7 integer |
/// | 12-15| Longitude | 4B   | ×10^7 integer |
/// | 16   | Status    | 1B   | Status code |
/// | 17-20| Timestamp | 4B   | Unix seconds |
/// | 21-24| Target ID | 4B   | 0=Broadcast, else UserID |
class SOSPacket {
  /// App header identifier (0xFFFF)
  static const int appHeader = 0xFFFF;

  /// Packet TTL in seconds (24 hours)
  static const int maxAgeSeconds = 86400;

  /// Unique user identifier (4 bytes)
  final int userId;

  /// Sequence number (increments on location change)
  final int sequence;

  /// Latitude × 10^7
  final int latitudeE7;

  /// Longitude × 10^7
  final int longitudeE7;

  /// Emergency status
  final SOSStatus status;

  /// Unix timestamp (seconds)
  final int timestamp;

  /// RSSI when received (not transmitted)
  int? rssi;

  /// Local database ID
  int? dbId;

  /// Whether this packet has been synced to cloud
  bool isSynced;

  /// Target User ID (0 = Broadcast/All)
  final int targetId;

  SOSPacket({
    required this.userId,
    required this.sequence,
    required this.latitudeE7,
    required this.longitudeE7,
    required this.status,
    required this.timestamp,
    this.rssi,
    this.dbId,
    this.isSynced = false,
    this.targetId = 0,
  });

  /// Generate a random 4-byte user ID
  static int generateUserId() {
    final random = Random.secure();
    return random.nextInt(0xFFFFFFFF);
  }

  /// Create packet from current location
  /// Create packet from current location
  factory SOSPacket.create({
    required int userId,
    required int sequence,
    required double latitude,
    required double longitude,
    required SOSStatus status,
    int targetId = 0,
  }) {
    return SOSPacket(
      userId: userId,
      sequence: sequence,
      latitudeE7: (latitude * 10000000).round(),
      longitudeE7: (longitude * 10000000).round(),
      status: status,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      targetId: targetId,
    );
  }

  /// Convert latitude to human-readable format
  double get latitude => latitudeE7 / 10000000.0;

  /// Convert longitude to human-readable format
  double get longitude => longitudeE7 / 10000000.0;

  /// Get packet age in seconds
  int get ageSeconds {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now - timestamp;
  }

  /// Check if packet has expired (>24 hours old)
  bool get isExpired => ageSeconds > maxAgeSeconds;

  /// Unique identifier for deduplication (userId + sequence)
  String get uniqueId => '${userId.toRadixString(16)}_$sequence';

  /// Create a new packet with incremented sequence (for location updates)
  SOSPacket incrementSequence({double? newLatitude, double? newLongitude}) {
    return SOSPacket(
      userId: userId,
      sequence: sequence + 1,
      latitudeE7: newLatitude != null
          ? (newLatitude * 10000000).round()
          : latitudeE7,
      longitudeE7: newLongitude != null
          ? (newLongitude * 10000000).round()
          : longitudeE7,
      status: status,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      targetId: targetId,
    );
  }

  /// Create a SAFE packet to cancel SOS
  SOSPacket markSafe() {
    return SOSPacket(
      userId: userId,
      sequence: sequence + 1,
      latitudeE7: latitudeE7,
      longitudeE7: longitudeE7,
      status: SOSStatus.safe,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      targetId: targetId,
    );
  }

  /// Serialize to bytes for BLE transmission (21 bytes)
  List<int> toBytes() {
    return [
      // Header (2 bytes)
      (appHeader >> 8) & 0xFF,
      appHeader & 0xFF,
      // User ID (4 bytes)
      (userId >> 24) & 0xFF,
      (userId >> 16) & 0xFF,
      (userId >> 8) & 0xFF,
      userId & 0xFF,
      // Sequence (2 bytes)
      (sequence >> 8) & 0xFF,
      sequence & 0xFF,
      // Latitude (4 bytes)
      (latitudeE7 >> 24) & 0xFF,
      (latitudeE7 >> 16) & 0xFF,
      (latitudeE7 >> 8) & 0xFF,
      latitudeE7 & 0xFF,
      // Longitude (4 bytes)
      (longitudeE7 >> 24) & 0xFF,
      (longitudeE7 >> 16) & 0xFF,
      (longitudeE7 >> 8) & 0xFF,
      longitudeE7 & 0xFF,
      // Status (1 byte)
      status.code,
      // Timestamp (4 bytes)
      (timestamp >> 24) & 0xFF,
      (timestamp >> 16) & 0xFF,
      (timestamp >> 8) & 0xFF,
      timestamp & 0xFF,
      // Target ID (4 bytes)
      (targetId >> 24) & 0xFF,
      (targetId >> 16) & 0xFF,
      (targetId >> 8) & 0xFF,
      targetId & 0xFF,
    ];
  }

  /// Deserialize from bytes
  factory SOSPacket.fromBytes(List<int> bytes, {int? rssi}) {
    if (bytes.length < 21) {
      throw ArgumentError(
        'Invalid packet size: ${bytes.length}, expected >= 21',
      );
    }

    // Verify header
    final header = (bytes[0] << 8) | bytes[1];
    if (header != appHeader) {
      throw ArgumentError('Invalid header: 0x${header.toRadixString(16)}');
    }

    return SOSPacket(
      userId: (bytes[2] << 24) | (bytes[3] << 16) | (bytes[4] << 8) | bytes[5],
      sequence: (bytes[6] << 8) | bytes[7],
      latitudeE7: _bytesToSignedInt32(bytes.sublist(8, 12)),
      longitudeE7: _bytesToSignedInt32(bytes.sublist(12, 16)),
      status: SOSStatus.fromCode(bytes[16]),
      timestamp:
          (bytes[17] << 24) | (bytes[18] << 16) | (bytes[19] << 8) | bytes[20],
      rssi: rssi,
      targetId: bytes.length >= 25
          ? (bytes[21] << 24) | (bytes[22] << 16) | (bytes[23] << 8) | bytes[24]
          : 0,
    );
  }

  /// Convert bytes to signed 32-bit integer
  static int _bytesToSignedInt32(List<int> bytes) {
    int value =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    // Handle negative numbers (two's complement)
    if (value >= 0x80000000) {
      value -= 0x100000000;
    }
    return value;
  }

  /// Convert to JSON for database storage
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'sequence': sequence,
      'latitudeE7': latitudeE7,
      'longitudeE7': longitudeE7,
      'status': status.code,
      'timestamp': timestamp,
      'rssi': rssi,
      'isSynced': isSynced ? 1 : 0,
      'targetId': targetId,
    };
  }

  /// Create from database JSON
  factory SOSPacket.fromJson(Map<String, dynamic> json) {
    return SOSPacket(
      userId: json['userId'] as int,
      sequence: json['sequence'] as int,
      latitudeE7: json['latitudeE7'] as int,
      longitudeE7: json['longitudeE7'] as int,
      status: SOSStatus.fromCode(json['status'] as int),
      timestamp: json['timestamp'] as int,
      rssi: json['rssi'] as int?,
      dbId: json['id'] as int?,
      isSynced: (json['isSynced'] as int?) == 1,
      targetId: json['targetId'] as int? ?? 0,
    );
  }

  @override
  String toString() {
    return 'SOSPacket(user: ${userId.toRadixString(16)}, seq: $sequence, '
        'status: ${status.label}, lat: $latitude, lon: $longitude, age: ${ageSeconds}s)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SOSPacket &&
        other.userId == userId &&
        other.sequence == sequence;
  }

  @override
  int get hashCode => userId.hashCode ^ sequence.hashCode;
}
