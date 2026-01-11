/// Battery saving modes for mesh operation
/// Extracted from settings_page.dart for modularity
enum BatteryMode {
  /// SOS Active: Always on, max range (6-8 hrs)
  sosActive(
    'SOS Active',
    'Always scanning, maximum reach',
    0, // Always on
    0, // No sleep
    7, // ~6-8 hrs
    'Max reaction time',
  ),

  /// Bridge Mode: 30s on, 30s off (12+ hrs)
  bridge(
    'Bridge Mode',
    '30s on / 30s off, balanced',
    30,
    30,
    12,
    'Fast updates',
  ),

  /// Battery Saver: 1 min on, 1 min off (24+ hrs)
  batterySaver(
    'Battery Saver',
    '1 min on / 1 min off, efficiency',
    60,
    60,
    24,
    'Power efficient',
  ),

  /// Custom: User-defined intervals
  custom(
    'Custom',
    'Set your own intervals',
    30, // Default
    30, // Default
    0, // Depends
    'Customizable',
  );

  final String label;
  final String description;
  final int scanSeconds;
  final int sleepSeconds;
  final int estimatedBatteryHours;
  final String reactionTime;

  const BatteryMode(
    this.label,
    this.description,
    this.scanSeconds,
    this.sleepSeconds,
    this.estimatedBatteryHours,
    this.reactionTime,
  );
}

/// BLE Version options
enum BLEVersion {
  legacy('BLE 4.x (Legacy)', 'Compatible with older devices'),
  modern('BLE 5.x', 'Extended range, faster transfer');

  final String label;
  final String description;

  const BLEVersion(this.label, this.description);
}
