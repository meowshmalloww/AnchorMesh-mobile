import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

/// Connectivity checker with ping verification
/// Detects actual internet availability, not just network connection
class ConnectivityChecker {
  static ConnectivityChecker? _instance;

  ConnectivityChecker._();

  static ConnectivityChecker get instance {
    _instance ??= ConnectivityChecker._();
    return _instance!;
  }

  /// Ping targets for internet check
  static const List<String> pingTargets = [
    'https://www.google.com',
    'https://www.cloudflare.com',
    'https://www.apple.com',
  ];

  /// Timeout for ping attempts
  static const Duration pingTimeout = Duration(seconds: 5);

  /// Consecutive failures needed to trigger offline mode
  static const int failuresForOffline = 3;

  int _consecutiveFailures = 0;
  bool _isOnline = true;
  Timer? _checkTimer;

  final _statusController = StreamController<bool>.broadcast();

  /// Stream of connectivity status changes
  Stream<bool> get statusStream => _statusController.stream;

  /// Current online status
  bool get isOnline => _isOnline;

  /// Check if internet is actually reachable
  Future<bool> checkInternet() async {
    for (final target in pingTargets) {
      try {
        final uri = Uri.parse(target);
        final client = HttpClient();
        client.connectionTimeout = pingTimeout;

        final request = await client.headUrl(uri);
        final response = await request.close().timeout(pingTimeout);

        if (response.statusCode == 200 || response.statusCode == 204) {
          _onSuccess();
          return true;
        }
      } catch (_) {
        // Try next target
      }
    }

    _onFailure();
    return false;
  }

  void _onSuccess() {
    _consecutiveFailures = 0;
    if (!_isOnline) {
      _isOnline = true;
      _statusController.add(true);
    }
  }

  void _onFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= failuresForOffline && _isOnline) {
      _isOnline = false;
      _statusController.add(false);
    }
  }

  /// Start periodic connectivity checking
  void startMonitoring({Duration interval = const Duration(minutes: 1)}) {
    stopMonitoring();
    _checkTimer = Timer.periodic(interval, (_) => checkInternet());
    // Check immediately
    checkInternet();
  }

  /// Stop periodic checking
  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _statusController.close();
  }
}

/// DEFCON-style alert levels
enum AlertLevel {
  /// Level 5: Peace - Normal operation
  peace(5, 'Normal', 'All systems normal'),

  /// Level 3: Warning - Disaster alert received
  warning(3, 'Warning', 'Disaster warning issued'),

  /// Level 1: Disaster - Confirmed emergency
  disaster(1, 'Disaster', 'Emergency confirmed');

  final int level;
  final String label;
  final String description;

  const AlertLevel(this.level, this.label, this.description);
}

/// Disaster monitoring service with rate limiting
class DisasterMonitor {
  static DisasterMonitor? _instance;

  DisasterMonitor._();

  static DisasterMonitor get instance {
    _instance ??= DisasterMonitor._();
    return _instance!;
  }

  AlertLevel _currentLevel = AlertLevel.peace;
  Timer? _checkTimer;
  Timer? _verificationTimer;
  int _verificationPingFailures = 0;

  // Rate limiting - cache API responses
  DateTime? _lastUSGSCheck;
  DateTime? _lastNOAACheck;
  bool? _cachedUSGSResult;
  Map<String, dynamic>? _cachedNOAAResult;

  // Rate limits (minimum time between API calls) - STRICT to conserve quota
  static const Duration usgsMinInterval = Duration(minutes: 60);
  static const Duration noaaMinInterval = Duration(minutes: 60);

  // Check interval (how often to check in background)
  static const Duration backgroundCheckInterval = Duration(minutes: 60);

  final _levelController = StreamController<AlertLevel>.broadcast();

  /// Stream of alert level changes
  Stream<AlertLevel> get levelStream => _levelController.stream;

  /// Current alert level
  AlertLevel get currentLevel => _currentLevel;

  /// Public getters for cached results (for UI display)
  bool? get cachedUSGSResult => _cachedUSGSResult;
  Map<String, dynamic>? get cachedNOAAResult => _cachedNOAAResult;

  /// USGS Earthquake API endpoint (free, no key needed)
  /// Limit: Reasonable use (every 15 min is fine)
  static const String usgsApi =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/significant_hour.geojson';

  /// NOAA Weather Alerts API (free, no key needed)
  /// Limit: Max 1 request per 10 seconds per IP
  static const String noaaApiBase = 'https://api.weather.gov/alerts/active';

  /// Check USGS for significant earthquakes (with rate limiting)
  Future<bool> checkUSGS({double minMagnitude = 6.0}) async {
    // Rate limiting: return cached result if checked recently
    if (_lastUSGSCheck != null &&
        DateTime.now().difference(_lastUSGSCheck!) < usgsMinInterval) {
      developer.log(
        'USGS: Using cached result (rate limited)',
        name: 'DisasterMonitor',
      );
      return _cachedUSGSResult ?? false;
    }

    try {
      developer.log(
        'USGS: Fetching earthquake data...',
        name: 'DisasterMonitor',
      );
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final request = await client.getUrl(Uri.parse(usgsApi));
      // Be a good citizen: set User-Agent
      request.headers.set('User-Agent', 'MeshSOS-App/1.0 (emergency-app)');

      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();

        // Parse JSON properly instead of regex
        final data = jsonDecode(body) as Map<String, dynamic>;
        final features = data['features'] as List? ?? [];

        bool hasSignificantQuake = false;
        for (final feature in features) {
          final properties = feature['properties'] as Map<String, dynamic>?;
          final mag = properties?['mag'] as num?;
          if (mag != null && mag >= minMagnitude) {
            developer.log(
              'USGS: Found M$mag earthquake!',
              name: 'DisasterMonitor',
            );
            hasSignificantQuake = true;
            break;
          }
        }

        // Cache result
        _lastUSGSCheck = DateTime.now();
        _cachedUSGSResult = hasSignificantQuake;

        developer.log(
          'USGS: Check complete. Found: $hasSignificantQuake',
          name: 'DisasterMonitor',
        );
        return hasSignificantQuake;
      }
    } catch (e) {
      developer.log('USGS: Error - $e', name: 'DisasterMonitor');
    }
    return false;
  }

  /// Check NOAA for severe weather alerts (with rate limiting)
  /// Only checks for Extreme/Severe alerts in user's area
  Future<Map<String, dynamic>?> checkNOAA({
    double? latitude,
    double? longitude,
  }) async {
    // Rate limiting
    if (_lastNOAACheck != null &&
        DateTime.now().difference(_lastNOAACheck!) < noaaMinInterval) {
      developer.log(
        'NOAA: Using cached result (rate limited)',
        name: 'DisasterMonitor',
      );
      return _cachedNOAAResult;
    }

    try {
      developer.log(
        'NOAA: Fetching weather alerts...',
        name: 'DisasterMonitor',
      );
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      // Build URL - can filter by point if location provided
      String url = '$noaaApiBase?status=actual&message_type=alert';
      if (latitude != null && longitude != null) {
        url = '$noaaApiBase?point=$latitude,$longitude';
      }

      final request = await client.getUrl(Uri.parse(url));
      // NOAA requires User-Agent
      request.headers.set('User-Agent', 'MeshSOS-App/1.0 (emergency-app)');
      request.headers.set('Accept', 'application/geo+json');

      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final features = data['features'] as List? ?? [];

        // Find most severe alert
        Map<String, dynamic>? severeAlert;
        for (final feature in features) {
          final properties = feature['properties'] as Map<String, dynamic>?;
          final severity = properties?['severity'] as String?;

          if (severity == 'Extreme' || severity == 'Severe') {
            severeAlert = {
              'event': properties?['event'],
              'severity': severity,
              'headline': properties?['headline'],
              'description': properties?['description'],
            };
            break;
          }
        }

        // Cache result
        _lastNOAACheck = DateTime.now();
        _cachedNOAAResult = severeAlert;

        developer.log(
          'NOAA: Check complete. Alerts: ${features.length}',
          name: 'DisasterMonitor',
        );
        return severeAlert;
      }
    } catch (e) {
      developer.log('NOAA: Error - $e', name: 'DisasterMonitor');
    }
    return null;
  }

  /// Trigger warning level and start verification
  void triggerWarning() {
    if (_currentLevel == AlertLevel.peace) {
      _currentLevel = AlertLevel.warning;
      _levelController.add(_currentLevel);
      _startVerification();
    }
  }

  /// Start verification mode (ping Google for 10 minutes)
  void _startVerification() {
    _verificationPingFailures = 0;
    _verificationTimer?.cancel();

    int checks = 0;
    _verificationTimer = Timer.periodic(const Duration(minutes: 1), (
      timer,
    ) async {
      checks++;
      final hasInternet = await ConnectivityChecker.instance.checkInternet();

      if (!hasInternet) {
        _verificationPingFailures++;
      }

      // After 10 checks or 10 consecutive failures
      if (checks >= 10 || _verificationPingFailures >= 10) {
        timer.cancel();
        if (_verificationPingFailures >= 3) {
          // Confirm disaster
          _currentLevel = AlertLevel.disaster;
          _levelController.add(_currentLevel);
        } else {
          // False alarm, return to peace
          _currentLevel = AlertLevel.peace;
          _levelController.add(_currentLevel);
        }
      }
    });
  }

  /// Manually set alert level
  void setLevel(AlertLevel level) {
    _currentLevel = level;
    _levelController.add(_currentLevel);

    if (level != AlertLevel.warning) {
      _verificationTimer?.cancel();
    }
  }

  /// Start background monitoring (check every 30 minutes - respects rate limits)
  void startMonitoring() {
    stopMonitoring();
    developer.log(
      'Starting disaster monitoring (interval: ${backgroundCheckInterval.inMinutes}min)',
      name: 'DisasterMonitor',
    );

    _checkTimer = Timer.periodic(backgroundCheckInterval, (_) async {
      await _runBackgroundCheck();
    });

    // Run first check after 5 seconds (not immediately to avoid startup spam)
    Future.delayed(const Duration(seconds: 5), _runBackgroundCheck);
  }

  Future<void> _runBackgroundCheck() async {
    developer.log(
      'Running background disaster check...',
      name: 'DisasterMonitor',
    );

    final hasEarthquake = await checkUSGS();
    final weatherAlert = await checkNOAA();

    if ((hasEarthquake || weatherAlert != null) &&
        _currentLevel == AlertLevel.peace) {
      developer.log(
        'Alert triggered! Earthquake: $hasEarthquake, Weather: ${weatherAlert?['event']}',
        name: 'DisasterMonitor',
      );
      triggerWarning();
    }
  }

  /// Stop monitoring
  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _verificationTimer?.cancel();
    _verificationTimer = null;
  }

  /// Clear cached results (force fresh API calls on next check)
  void clearCache() {
    _lastUSGSCheck = null;
    _lastNOAACheck = null;
    _cachedUSGSResult = null;
    _cachedNOAAResult = null;
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _levelController.close();
  }
}
