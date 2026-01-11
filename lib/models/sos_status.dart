import 'package:flutter/material.dart';

/// Extended SOS Status Codes
/// Based on emergency response protocols
enum SOSStatus {
  /// 0x00: User is safe, no help needed
  safe(0x00, 'SAFE', 'I am safe'),

  /// 0x01: General SOS, needs rescue
  sos(0x01, 'EMERGENCY', 'Need rescue'),

  /// 0x02: Medical emergency
  medical(0x02, 'MEDICAL', 'Medical emergency'),

  /// 0x03: Trapped under debris
  trapped(0x03, 'TRAPPED', 'Trapped/Pinned'),

  /// 0x04: Needs water/food/supplies
  supplies(0x04, 'SUPPLIES', 'Need water/food');

  final int code;
  final String label;
  final String description;

  const SOSStatus(this.code, this.label, this.description);

  /// Get status from byte code
  static SOSStatus fromCode(int code) {
    return SOSStatus.values.firstWhere(
      (s) => s.code == code,
      orElse: () => SOSStatus.safe,
    );
  }

  /// Get color for UI display
  int get colorValue {
    switch (this) {
      case SOSStatus.safe:
        return 0xFF4CAF50; // Green
      case SOSStatus.sos:
        return 0xFFF44336; // Red
      case SOSStatus.medical:
        return 0xFFE91E63; // Pink
      case SOSStatus.trapped:
        return 0xFFFF5722; // Deep Orange
      case SOSStatus.supplies:
        return 0xFFFF9800; // Orange
    }
  }

  /// Get icon for UI display
  IconData get icon {
    switch (this) {
      case SOSStatus.safe:
        return Icons.check_circle;
      case SOSStatus.sos:
        return Icons.emergency;
      case SOSStatus.medical:
        return Icons.medical_services;
      case SOSStatus.trapped:
        return Icons
            .warning; // best approximation for trapped if person_pin not avail or specific
      case SOSStatus.supplies:
        return Icons.local_drink;
    }
  }

  /// Get emoji for notifications
  String get emoji {
    switch (this) {
      case SOSStatus.safe:
        return '✅';
      case SOSStatus.sos:
        return '🆘';
      case SOSStatus.medical:
        return '🏥';
      case SOSStatus.trapped:
        return '🚨';
      case SOSStatus.supplies:
        return '📦';
    }
  }
}
