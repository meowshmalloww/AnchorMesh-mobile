/// Connection state for BLE mesh networking
/// Extracted from ble_service.dart for modularity
enum BLEConnectionState {
  unavailable,
  bluetoothOff,
  idle,
  broadcasting,
  scanning,
  meshActive,
}

/// Echo event when own packet is detected being relayed
class EchoEvent {
  final int userId;
  final int rssi;
  final DateTime timestamp;

  EchoEvent({
    required this.userId,
    required this.rssi,
    required this.timestamp,
  });
}

/// Verification status for SOS signals
class VerificationStatus {
  final int userId;
  final int confirmations;
  final bool isVerified;
  final List<int> confirmingDevices;

  VerificationStatus({
    required this.userId,
    required this.confirmations,
    required this.isVerified,
    required this.confirmingDevices,
  });

  static const int requiredConfirmations = 3;
}
