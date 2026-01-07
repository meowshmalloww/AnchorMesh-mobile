/// Device Info Model
/// Represents local and peer device information

import 'sos_alert.dart';

/// BLE capabilities of a device
class BleCapabilities {
  final bool supportsExtended; // BLE 5.0 extended advertising
  final bool supportsMesh;
  final int maxMtu;

  const BleCapabilities({
    this.supportsExtended = false,
    this.supportsMesh = true,
    this.maxMtu = 247,
  });

  Map<String, dynamic> toJson() => {
        'supportsExtended': supportsExtended,
        'supportsMesh': supportsMesh,
        'maxMtu': maxMtu,
      };

  factory BleCapabilities.fromJson(Map<String, dynamic> json) {
    return BleCapabilities(
      supportsExtended: json['supportsExtended'] as bool? ?? false,
      supportsMesh: json['supportsMesh'] as bool? ?? true,
      maxMtu: json['maxMtu'] as int? ?? 247,
    );
  }
}

/// Platform type
enum DevicePlatform {
  ios,
  android,
  web;

  String toJson() => name;

  static DevicePlatform fromJson(String json) {
    return DevicePlatform.values.firstWhere(
      (e) => e.name == json,
      orElse: () => DevicePlatform.android,
    );
  }
}

/// Local device information
class LocalDevice {
  final String deviceId;
  final DevicePlatform platform;
  final String? appVersion;
  final String? osVersion;
  final String? deviceModel;
  final BleCapabilities bleCapabilities;

  GeoLocation? lastKnownLocation;
  String? authToken;
  String? appSignature;

  LocalDevice({
    required this.deviceId,
    required this.platform,
    this.appVersion,
    this.osVersion,
    this.deviceModel,
    this.bleCapabilities = const BleCapabilities(),
    this.lastKnownLocation,
    this.authToken,
    this.appSignature,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'platform': platform.toJson(),
        if (appVersion != null) 'appVersion': appVersion,
        if (osVersion != null) 'osVersion': osVersion,
        if (deviceModel != null) 'deviceModel': deviceModel,
        'bleCapabilities': bleCapabilities.toJson(),
        if (lastKnownLocation != null) 'location': lastKnownLocation!.toJson(),
      };

  factory LocalDevice.fromJson(Map<String, dynamic> json) {
    return LocalDevice(
      deviceId: json['deviceId'] as String,
      platform: DevicePlatform.fromJson(json['platform'] as String),
      appVersion: json['appVersion'] as String?,
      osVersion: json['osVersion'] as String?,
      deviceModel: json['deviceModel'] as String?,
      bleCapabilities: json['bleCapabilities'] != null
          ? BleCapabilities.fromJson(
              json['bleCapabilities'] as Map<String, dynamic>)
          : const BleCapabilities(),
      lastKnownLocation: json['location'] != null
          ? GeoLocation.fromJson(json['location'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Registration response from server
class DeviceRegistrationResponse {
  final String deviceId;
  final String token;
  final String appSignature;
  final String expiresIn;

  const DeviceRegistrationResponse({
    required this.deviceId,
    required this.token,
    required this.appSignature,
    required this.expiresIn,
  });

  factory DeviceRegistrationResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return DeviceRegistrationResponse(
      deviceId: (data['device'] as Map<String, dynamic>)['deviceId'] as String,
      token: data['token'] as String,
      appSignature: data['appSignature'] as String,
      expiresIn: data['expiresIn'] as String,
    );
  }
}
