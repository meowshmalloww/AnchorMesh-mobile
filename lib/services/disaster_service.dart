import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import '../models/disaster_event.dart';
import 'connectivity_service.dart';

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

class DisasterService {
  static DisasterService? _instance;
  DisasterService._();
  static DisasterService get instance {
    _instance ??= DisasterService._();
    return _instance!;
  }

  // State
  List<DisasterEvent> _activeEvents = [];
  AlertLevel _currentLevel = AlertLevel.peace;
  final _levelController = StreamController<AlertLevel>.broadcast();
  final _eventsController = StreamController<List<DisasterEvent>>.broadcast();

  Stream<AlertLevel> get levelStream => _levelController.stream;
  Stream<List<DisasterEvent>> get eventsStream => _eventsController.stream;
  List<DisasterEvent> get activeEvents => _activeEvents;

  // USGS API: All earthquakes in last 24 hours
  static const String usgsApi =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.geojson';
  // I will use 2.5 day to ensure we cover "last 24 hours" comfortably, or specific 1.0_day
  // "all_day" is usually "all_day" (past 24h). Let's use 'all_day' for significant?
  // User asked for "all disaster events reported globally within the last 24 hours".
  // 'all_day.geojson' includes all earthquakes from the past day.
  static const String usgsUrl =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson';

  // NOAA API
  static const String noaaApi =
      'https://api.weather.gov/alerts/active?severity=Severe,Extreme';

  DateTime? _lastCheck;
  static const Duration checkInterval = Duration(minutes: 15);

  void startMonitoring() {
    _fetchEvents();
    Timer.periodic(checkInterval, (_) => _fetchEvents());
  }

  Future<void> _fetchEvents() async {
    // Rate limiting
    if (_lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < checkInterval) {
      return;
    }
    _lastCheck = DateTime.now();

    // Check connectivity first
    if (!await ConnectivityChecker.instance.checkInternet()) return;

    final List<DisasterEvent> newEvents = [];

    // 1. Fetch Earthquakes
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(usgsUrl));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        final features = data['features'] as List;

        for (var f in features) {
          final props = f['properties'];
          final geom = f['geometry'];
          final coords = geom['coordinates'] as List; // [lon, lat, depth]
          final time = DateTime.fromMillisecondsSinceEpoch(props['time']);

          // Filter > 24 hours
          if (DateTime.now().difference(time).inHours > 24) continue;

          newEvents.add(
            DisasterEvent(
              id: f['id'],
              type: 'earthquake',
              title: props['title'] ?? 'Earthquake',
              description: 'Magnitude ${props['mag']}',
              severity: (props['mag'] ?? 0) > 6.0 ? 'High' : 'Medium',
              time: time,
              latitude: (coords[1] as num).toDouble(),
              longitude: (coords[0] as num).toDouble(),
              sourceUrl: props['url'],
            ),
          );
        }
      }
    } catch (e) {
      developer.log('Error fetching USGS: $e');
    }

    // 2. Fetch NOAA Severe Weather Alerts (US Only)
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(noaaApi));
      request.headers.set('User-Agent', 'ResQ Emergency App');
      request.headers.set('Accept', 'application/geo+json');
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        final features = data['features'] as List? ?? [];

        for (var f in features) {
          final props = f['properties'];
          final geom = f['geometry'];

          // Skip if no geometry or no coordinates
          if (geom == null) continue;

          // Parse time
          final effectiveStr = props['effective'];
          DateTime? time;
          if (effectiveStr != null) {
            time = DateTime.tryParse(effectiveStr);
          }
          time ??= DateTime.now();

          // Filter > 24 hours
          if (DateTime.now().difference(time).inHours > 24) continue;

          // Extract representative coordinate (first point of polygon)
          double? lat;
          double? lon;

          if (geom['type'] == 'Polygon' && geom['coordinates'] != null) {
            final ring = geom['coordinates'][0] as List;
            if (ring.isNotEmpty) {
              final firstPoint = ring[0] as List;
              lon = (firstPoint[0] as num).toDouble();
              lat = (firstPoint[1] as num).toDouble();
            }
          } else if (geom['type'] == 'Point' && geom['coordinates'] != null) {
            final coords = geom['coordinates'] as List;
            lon = (coords[0] as num).toDouble();
            lat = (coords[1] as num).toDouble();
          }

          // Skip if no valid coordinates
          if (lat == null || lon == null) continue;

          final severity = props['severity'] ?? 'Unknown';
          final eventType = props['event'] ?? 'Weather Alert';

          newEvents.add(
            DisasterEvent(
              id: props['id'] ?? 'noaa_${newEvents.length}',
              type: 'weather',
              title: eventType,
              description: props['headline'] ?? eventType,
              severity: severity == 'Extreme' ? 'High' : 'Medium',
              time: time,
              latitude: lat,
              longitude: lon,
              sourceUrl: props['web'],
            ),
          );
        }
      }
    } catch (e) {
      developer.log('Error fetching NOAA: $e');
    }

    _activeEvents = newEvents;
    _eventsController.add(_activeEvents);

    // Auto-alert
    if (_activeEvents.any(
      (e) => e.severity == 'High' || e.severity == 'Extreme',
    )) {
      if (_currentLevel == AlertLevel.peace) {
        _currentLevel = AlertLevel.warning;
        _levelController.add(_currentLevel);
      }
    }
  }

  Future<void> refresh() => _fetchEvents();
}
