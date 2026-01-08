import 'dart:math';
import 'dart:collection';

/// RSSI-based distance calculator with signal smoothing
///
/// Distance Formula: d = 10^((MeasuredPower - RSSI) / (10 * N))
/// - MeasuredPower: RSSI at exactly 1 meter (default: -69 dBm)
/// - N: Environmental factor (2=open, 4=rubble, 3=disaster average)
class RSSICalculator {
  /// RSSI at 1 meter distance (calibration value)
  static const double measuredPower = -69.0;

  /// Environmental factors
  static const double envOpenSpace = 2.0;
  static const double envIndoor = 3.0;
  static const double envRubble = 4.0;
  static const double envDisasterAvg = 3.0;

  /// EMA smoothing factor (0.1 = very smooth, 0.5 = responsive)
  static const double emaSmoothingFactor = 0.3;

  /// Sample history for moving average
  final Map<String, Queue<int>> _rssiHistory = {};
  final Map<String, double> _emaValues = {};

  /// Max samples to keep per device
  static const int maxHistorySize = 10;

  /// Calculate distance from RSSI
  /// Returns distance in meters
  static double calculateDistance(
    int rssi, {
    double environmentFactor = envDisasterAvg,
    double? customMeasuredPower,
  }) {
    final mp = customMeasuredPower ?? measuredPower;
    final exponent = (mp - rssi) / (10 * environmentFactor);
    return pow(10, exponent).toDouble();
  }

  /// Add RSSI sample for a device and get smoothed value
  double addSample(String deviceId, int rssi) {
    // Initialize history if needed
    _rssiHistory.putIfAbsent(deviceId, () => Queue<int>());
    final history = _rssiHistory[deviceId]!;

    // Add to history
    history.add(rssi);
    if (history.length > maxHistorySize) {
      history.removeFirst();
    }

    // Calculate EMA
    if (_emaValues.containsKey(deviceId)) {
      _emaValues[deviceId] =
          emaSmoothingFactor * rssi +
          (1 - emaSmoothingFactor) * _emaValues[deviceId]!;
    } else {
      _emaValues[deviceId] = rssi.toDouble();
    }

    return _emaValues[deviceId]!;
  }

  /// Get smoothed RSSI for a device
  double? getSmoothedRSSI(String deviceId) {
    return _emaValues[deviceId];
  }

  /// Get simple moving average RSSI
  double? getSMArssi(String deviceId) {
    final history = _rssiHistory[deviceId];
    if (history == null || history.isEmpty) return null;
    return history.reduce((a, b) => a + b) / history.length;
  }

  /// Get smoothed distance for a device
  double? getSmoothedDistance(
    String deviceId, {
    double envFactor = envDisasterAvg,
  }) {
    final rssi = _emaValues[deviceId];
    if (rssi == null) return null;
    return calculateDistance(rssi.round(), environmentFactor: envFactor);
  }

  /// Get proximity description
  static String getProximityDescription(double distanceMeters) {
    if (distanceMeters < 2) return 'Very Close (< 2m)';
    if (distanceMeters < 5) return 'Close (2-5m)';
    if (distanceMeters < 10) return 'Nearby (5-10m)';
    if (distanceMeters < 30) return 'In Range (10-30m)';
    if (distanceMeters < 100) return 'Far (30-100m)';
    return 'Very Far (> 100m)';
  }

  /// Get signal strength category
  static String getSignalStrength(int rssi) {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Good';
    if (rssi >= -70) return 'Fair';
    if (rssi >= -80) return 'Weak';
    return 'Very Weak';
  }

  /// Clear history for a device
  void clearDevice(String deviceId) {
    _rssiHistory.remove(deviceId);
    _emaValues.remove(deviceId);
  }

  /// Clear all history
  void clearAll() {
    _rssiHistory.clear();
    _emaValues.clear();
  }
}

/// Kalman Filter for RSSI smoothing
/// Provides better noise reduction than simple moving average
class KalmanFilter {
  double _estimate;
  double _errorEstimate;
  final double _errorMeasurement;
  final double _processNoise;

  /// Create a Kalman filter
  /// - initialEstimate: Starting RSSI estimate (e.g., -70)
  /// - errorMeasurement: Measurement noise (higher = less trust in measurements, e.g., 4.0)
  /// - processNoise: How fast the actual value changes (e.g., 0.5)
  KalmanFilter({
    double initialEstimate = -70.0,
    double errorMeasurement = 4.0,
    double processNoise = 0.5,
  }) : _estimate = initialEstimate,
       _errorEstimate = errorMeasurement,
       _errorMeasurement = errorMeasurement,
       _processNoise = processNoise;

  /// Process a new measurement and return filtered value
  double filter(double measurement) {
    // Prediction
    _errorEstimate = _errorEstimate + _processNoise;

    // Kalman Gain
    final kalmanGain = _errorEstimate / (_errorEstimate + _errorMeasurement);

    // Update estimate
    _estimate = _estimate + kalmanGain * (measurement - _estimate);

    // Update error estimate
    _errorEstimate = (1 - kalmanGain) * _errorEstimate;

    return _estimate;
  }

  /// Get current estimate
  double get estimate => _estimate;

  /// Reset the filter
  void reset({double? initialEstimate}) {
    _estimate = initialEstimate ?? -70.0;
    _errorEstimate = _errorMeasurement;
  }
}

/// Direction finding using compass + RSSI
class DirectionFinder {
  /// RSSI readings at different compass headings
  final Map<int, List<int>> _headingReadings = {};

  /// Add RSSI reading at a compass heading
  void addReading(double heading, int rssi) {
    // Round heading to nearest 10 degrees
    final roundedHeading = ((heading / 10).round() * 10) % 360;
    _headingReadings.putIfAbsent(roundedHeading, () => []);
    _headingReadings[roundedHeading]!.add(rssi);
  }

  /// Get the heading with strongest signal
  int? getStrongestHeading() {
    if (_headingReadings.isEmpty) return null;

    int? bestHeading;
    double bestAvg = double.negativeInfinity;

    for (final entry in _headingReadings.entries) {
      if (entry.value.isEmpty) continue;
      final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
      if (avg > bestAvg) {
        bestAvg = avg;
        bestHeading = entry.key;
      }
    }

    return bestHeading;
  }

  /// Get sorted list of headings by signal strength
  List<MapEntry<int, double>> getRankedHeadings() {
    final averages = <MapEntry<int, double>>[];

    for (final entry in _headingReadings.entries) {
      if (entry.value.isEmpty) continue;
      final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
      averages.add(MapEntry(entry.key, avg));
    }

    averages.sort((a, b) => b.value.compareTo(a.value));
    return averages;
  }

  /// Check if we have enough readings for direction determination
  bool hasEnoughData() {
    // Need at least 6 different headings with data
    return _headingReadings.entries.where((e) => e.value.isNotEmpty).length >=
        6;
  }

  /// Clear all readings
  void clear() {
    _headingReadings.clear();
  }
}
