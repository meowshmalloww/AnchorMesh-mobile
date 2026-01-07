/// Peer Device Model
/// Represents a discovered device in the BLE mesh network

import 'dart:math' as math;
import 'device_info.dart';
import 'sos_alert.dart';

/// Connection state with a peer
enum PeerConnectionState {
  discovered,
  connecting,
  connected,
  disconnecting,
  disconnected,
  error;
}

/// Peer device discovered via BLE
class PeerDevice {
  final String deviceId;
  final String bleAddress;
  final String? name;

  PeerConnectionState connectionState;
  int rssi;
  DateTime lastSeen;
  bool hasInternet;
  BleCapabilities? capabilities;
  GeoLocation? lastKnownLocation;

  // Mesh networking stats
  int messagesRelayed;
  int messagesReceived;
  DateTime? lastMessageTime;

  PeerDevice({
    required this.deviceId,
    required this.bleAddress,
    this.name,
    this.connectionState = PeerConnectionState.discovered,
    this.rssi = -100,
    DateTime? lastSeen,
    this.hasInternet = false,
    this.capabilities,
    this.lastKnownLocation,
    this.messagesRelayed = 0,
    this.messagesReceived = 0,
    this.lastMessageTime,
  }) : lastSeen = lastSeen ?? DateTime.now();

  /// Estimated distance based on RSSI (rough approximation)
  double? get estimatedDistanceMeters {
    if (rssi >= 0) return null;
    // Using simple path loss model: RSSI = -10 * n * log10(d) + A
    // Where n ≈ 2 (free space), A ≈ -59 (RSSI at 1m)
    const txPower = -59;
    const n = 2.0;
    final distance = math.pow(10, (txPower - rssi) / (10 * n)).toDouble();
    return distance;
  }

  /// Signal strength category
  String get signalStrength {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Good';
    if (rssi >= -70) return 'Fair';
    if (rssi >= -80) return 'Weak';
    return 'Very Weak';
  }

  /// Check if the peer is recently active
  bool get isActive {
    final threshold = DateTime.now().subtract(const Duration(minutes: 5));
    return lastSeen.isAfter(threshold);
  }

  /// Update peer information from advertisement
  void updateFromAdvertisement({
    int? rssi,
    bool? hasInternet,
    GeoLocation? location,
  }) {
    if (rssi != null) this.rssi = rssi;
    if (hasInternet != null) this.hasInternet = hasInternet;
    if (location != null) lastKnownLocation = location;
    lastSeen = DateTime.now();
  }

  /// Record a message exchange
  void recordMessage({bool sent = false, bool received = false}) {
    if (sent) messagesRelayed++;
    if (received) messagesReceived++;
    lastMessageTime = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'bleAddress': bleAddress,
        if (name != null) 'name': name,
        'connectionState': connectionState.name,
        'rssi': rssi,
        'lastSeen': lastSeen.toIso8601String(),
        'hasInternet': hasInternet,
        if (capabilities != null) 'capabilities': capabilities!.toJson(),
        if (lastKnownLocation != null)
          'location': lastKnownLocation!.toJson(),
        'messagesRelayed': messagesRelayed,
        'messagesReceived': messagesReceived,
      };

  factory PeerDevice.fromJson(Map<String, dynamic> json) {
    return PeerDevice(
      deviceId: json['deviceId'] as String,
      bleAddress: json['bleAddress'] as String,
      name: json['name'] as String?,
      connectionState: PeerConnectionState.values.firstWhere(
        (e) => e.name == json['connectionState'],
        orElse: () => PeerConnectionState.discovered,
      ),
      rssi: json['rssi'] as int? ?? -100,
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'] as String)
          : null,
      hasInternet: json['hasInternet'] as bool? ?? false,
      capabilities: json['capabilities'] != null
          ? BleCapabilities.fromJson(
              json['capabilities'] as Map<String, dynamic>)
          : null,
      lastKnownLocation: json['location'] != null
          ? GeoLocation.fromJson(json['location'] as Map<String, dynamic>)
          : null,
      messagesRelayed: json['messagesRelayed'] as int? ?? 0,
      messagesReceived: json['messagesReceived'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'PeerDevice($deviceId, signal: $signalStrength, internet: $hasInternet)';
}
