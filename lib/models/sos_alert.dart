/// SOS Alert Model
/// Represents an emergency SOS message in the mesh network

import 'dart:convert';

/// Emergency types
enum EmergencyType {
  medical,
  fire,
  security,
  naturalDisaster,
  accident,
  other;

  String get displayName {
    switch (this) {
      case EmergencyType.medical:
        return 'Medical Emergency';
      case EmergencyType.fire:
        return 'Fire';
      case EmergencyType.security:
        return 'Security Threat';
      case EmergencyType.naturalDisaster:
        return 'Natural Disaster';
      case EmergencyType.accident:
        return 'Accident';
      case EmergencyType.other:
        return 'Other Emergency';
    }
  }

  String toJson() => name;

  static EmergencyType fromJson(String json) {
    return EmergencyType.values.firstWhere(
      (e) => e.name == json || e.name == json.replaceAll('_', ''),
      orElse: () => EmergencyType.other,
    );
  }
}

/// Message priority levels
enum MessagePriority {
  low,
  medium,
  high,
  critical;

  String toJson() => name;

  static MessagePriority fromJson(String json) {
    return MessagePriority.values.firstWhere(
      (e) => e.name == json,
      orElse: () => MessagePriority.high,
    );
  }
}

/// Alert status
enum AlertStatus {
  pending,
  sent,
  delivered,
  acknowledged,
  resolved,
  cancelled,
  expired;

  String toJson() => name;

  static AlertStatus fromJson(String json) {
    return AlertStatus.values.firstWhere(
      (e) => e.name == json,
      orElse: () => AlertStatus.pending,
    );
  }
}

/// Geographic location
class GeoLocation {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final DateTime? timestamp;

  const GeoLocation({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (altitude != null) 'altitude': altitude,
        if (accuracy != null) 'accuracy': accuracy,
        if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
      };

  factory GeoLocation.fromJson(Map<String, dynamic> json) {
    return GeoLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: json['altitude'] != null
          ? (json['altitude'] as num).toDouble()
          : null,
      accuracy: json['accuracy'] != null
          ? (json['accuracy'] as num).toDouble()
          : null,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  @override
  String toString() =>
      'GeoLocation(lat: ${latitude.toStringAsFixed(6)}, lon: ${longitude.toStringAsFixed(6)})';
}

/// Relay hop information
class RelayHop {
  final String deviceId;
  final DateTime timestamp;
  final bool hadInternet;

  const RelayHop({
    required this.deviceId,
    required this.timestamp,
    this.hadInternet = false,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'timestamp': timestamp.toIso8601String(),
        'hadInternet': hadInternet,
      };

  factory RelayHop.fromJson(Map<String, dynamic> json) {
    return RelayHop(
      deviceId: json['deviceId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      hadInternet: json['hadInternet'] as bool? ?? false,
    );
  }
}

/// Main SOS Alert class
class SOSAlert {
  final String messageId;
  final String originatorDeviceId;
  final String appSignature;
  final EmergencyType emergencyType;
  final MessagePriority priority;
  final GeoLocation location;
  final String? message;
  final String? signature;
  final DateTime originatedAt;
  final DateTime expiresAt;

  // Relay tracking
  int hopCount;
  List<RelayHop> relayChain;

  // Status tracking
  AlertStatus status;
  bool deliveredToServer;
  DateTime? acknowledgedAt;

  SOSAlert({
    required this.messageId,
    required this.originatorDeviceId,
    required this.appSignature,
    required this.emergencyType,
    required this.location,
    this.priority = MessagePriority.critical,
    this.message,
    this.signature,
    DateTime? originatedAt,
    DateTime? expiresAt,
    this.hopCount = 0,
    List<RelayHop>? relayChain,
    this.status = AlertStatus.pending,
    this.deliveredToServer = false,
    this.acknowledgedAt,
  })  : originatedAt = originatedAt ?? DateTime.now(),
        expiresAt = expiresAt ?? DateTime.now().add(const Duration(hours: 24)),
        relayChain = relayChain ?? [];

  /// Check if the alert has expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Check if this is a relayed message (not from originator)
  bool get isRelayed => hopCount > 0;

  /// Add a relay hop
  void addRelayHop(String deviceId, bool hadInternet) {
    relayChain.add(RelayHop(
      deviceId: deviceId,
      timestamp: DateTime.now(),
      hadInternet: hadInternet,
    ));
    hopCount = relayChain.length;
  }

  /// Create a copy for relaying
  SOSAlert copyForRelay(String relayingDeviceId, bool hasInternet) {
    final copy = SOSAlert(
      messageId: messageId,
      originatorDeviceId: originatorDeviceId,
      appSignature: appSignature,
      emergencyType: emergencyType,
      location: location,
      priority: priority,
      message: message,
      signature: signature,
      originatedAt: originatedAt,
      expiresAt: expiresAt,
      hopCount: hopCount + 1,
      relayChain: List.from(relayChain),
      status: status,
    );
    copy.addRelayHop(relayingDeviceId, hasInternet);
    return copy;
  }

  /// Convert to JSON for transmission
  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'originatorDeviceId': originatorDeviceId,
        'appSignature': appSignature,
        'emergencyType': emergencyType.toJson(),
        'priority': priority.toJson(),
        'location': location.toJson(),
        if (message != null) 'message': message,
        if (signature != null) 'signature': signature,
        'originatedAt': originatedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'hopCount': hopCount,
        'relayChain': relayChain.map((r) => r.toJson()).toList(),
        'status': status.toJson(),
      };

  /// Create from JSON
  factory SOSAlert.fromJson(Map<String, dynamic> json) {
    return SOSAlert(
      messageId: json['messageId'] as String,
      originatorDeviceId: json['originatorDeviceId'] as String,
      appSignature: json['appSignature'] as String,
      emergencyType: EmergencyType.fromJson(json['emergencyType'] as String),
      priority: MessagePriority.fromJson(json['priority'] as String? ?? 'high'),
      location: GeoLocation.fromJson(json['location'] as Map<String, dynamic>),
      message: json['message'] as String?,
      signature: json['signature'] as String?,
      originatedAt: DateTime.parse(json['originatedAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      hopCount: json['hopCount'] as int? ?? 0,
      relayChain: (json['relayChain'] as List<dynamic>?)
              ?.map((r) => RelayHop.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      status: AlertStatus.fromJson(json['status'] as String? ?? 'pending'),
    );
  }

  /// Encode for BLE transmission (compact binary format)
  List<int> toBytes() {
    final jsonStr = jsonEncode(toJson());
    return utf8.encode(jsonStr);
  }

  /// Decode from BLE transmission
  static SOSAlert? fromBytes(List<int> bytes) {
    try {
      final jsonStr = utf8.decode(bytes);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return SOSAlert.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  @override
  String toString() =>
      'SOSAlert(id: $messageId, type: ${emergencyType.displayName}, status: $status)';
}
