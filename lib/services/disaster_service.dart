import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'package:geolocator/geolocator.dart';
import '../config/api_config.dart';
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

  // Auto-unlock SOS state
  bool _sosAutoUnlocked = false;
  final _sosUnlockController = StreamController<bool>.broadcast();

  Stream<AlertLevel> get levelStream => _levelController.stream;
  Stream<List<DisasterEvent>> get eventsStream => _eventsController.stream;
  Stream<bool> get sosUnlockStream => _sosUnlockController.stream;
  List<DisasterEvent> get activeEvents => _activeEvents;
  bool get isSosAutoUnlocked => _sosAutoUnlocked;
  AlertLevel get currentLevel => _currentLevel;

  // Rate limiting - independent timers (uses ApiConfig)
  DateTime? _lastUsgsCheck;
  DateTime? _lastNoaaCheck;
  DateTime? _lastGdacsCheck;
  DateTime? _lastGooglePing;
  Duration get _rateLimit =>
      Duration(minutes: ApiConfig.disasterCheckIntervalMinutes);
  Duration get _googlePingLimit =>
      Duration(minutes: ApiConfig.googlePingIntervalMinutes);

  // Cache keys
  static const String _cacheKey = 'disaster_events_cache';
  static const String _cacheTimestampKey = 'disaster_cache_timestamp';

  Timer? _monitorTimer;

  void startMonitoring() {
    _loadCachedEvents();
    _fetchAllSources();
    _monitorTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _fetchAllSources(),
    );
  }

  void stopMonitoring() {
    _monitorTimer?.cancel();
  }

  Future<void> _fetchAllSources() async {
    // Check connectivity first
    if (!await ConnectivityChecker.instance.checkInternet()) {
      // Offline - use cached data only, but try stage-2 unlock check
      await _checkAutoUnlockSOS();
      return;
    }

    final now = DateTime.now();
    final List<DisasterEvent> newEvents = [];

    // 1. Fetch USGS (rate limited)
    if (_lastUsgsCheck == null ||
        now.difference(_lastUsgsCheck!) >= _rateLimit) {
      final usgsEvents = await _fetchUsgs();
      newEvents.addAll(usgsEvents);
      _lastUsgsCheck = now;
    }

    // 2. Fetch NOAA (rate limited)
    if (_lastNoaaCheck == null ||
        now.difference(_lastNoaaCheck!) >= _rateLimit) {
      final noaaEvents = await _fetchNoaa();
      newEvents.addAll(noaaEvents);
      _lastNoaaCheck = now;
    }

    // 3. Fetch GDACS (rate limited)
    if (_lastGdacsCheck == null ||
        now.difference(_lastGdacsCheck!) >= _rateLimit) {
      final gdacsEvents = await _fetchGdacs();
      newEvents.addAll(gdacsEvents);
      _lastGdacsCheck = now;
    }

    // Merge with cached and dedupe
    final cachedEvents = await _loadCachedEvents();
    final mergedEvents = _mergeAndDedupe(cachedEvents, newEvents);

    // Filter expired (>24h)
    final freshEvents = mergedEvents
        .where((e) => DateTime.now().difference(e.time).inHours < 24)
        .toList();
    freshEvents.sort(
      (a, b) => b.time.compareTo(a.time),
    ); // Sort by time, newest first

    _activeEvents = freshEvents;
    _eventsController.add(_activeEvents);

    // Cache updated events
    await _saveEventsToCache(_activeEvents);

    // Check for auto-unlock conditions and update alert level with proximity check
    await _updateAlertLevel();
    await _checkAutoUnlockSOS();
  }

  // ==================
  // USGS Earthquakes
  // ==================
  Future<List<DisasterEvent>> _fetchUsgs() async {
    final List<DisasterEvent> events = [];
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(
        Uri.parse(ApiConfig.usgsEarthquakeApi),
      );
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        final features = data['features'] as List;

        for (var f in features) {
          final props = f['properties'];
          final geom = f['geometry'];
          final coords = geom['coordinates'] as List;
          final time = DateTime.fromMillisecondsSinceEpoch(props['time']);
          final mag = (props['mag'] as num?)?.toDouble() ?? 0.0;

          // Filter >24 hours
          if (DateTime.now().difference(time).inHours > 24) continue;

          events.add(
            DisasterEvent(
              id: f['id'],
              type: 'earthquake',
              title: props['title'] ?? 'Earthquake M$mag',
              description: 'Magnitude $mag',
              severity: mag >= 6.0 ? 'High' : (mag >= 4.5 ? 'Medium' : 'Low'),
              time: time,
              latitude: (coords[1] as num).toDouble(),
              longitude: (coords[0] as num).toDouble(),
              sourceUrl: props['url'],
              magnitude: mag,
            ),
          );
        }
      }
      developer.log('USGS: Fetched ${events.length} earthquakes');
    } catch (e) {
      developer.log('Error fetching USGS: $e');
    }
    return events;
  }

  // ==================
  // NOAA Weather
  // ==================
  Future<List<DisasterEvent>> _fetchNoaa() async {
    final List<DisasterEvent> events = [];
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(ApiConfig.noaaAlertsApi));
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
          if (geom == null) continue;

          DateTime? time;
          final effectiveStr = props['effective'];
          if (effectiveStr != null) {
            time = DateTime.tryParse(effectiveStr);
          }
          time ??= DateTime.now();
          if (DateTime.now().difference(time).inHours > 24) continue;

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
          if (lat == null || lon == null) continue;

          final severity = props['severity'] ?? 'Unknown';
          final eventType = props['event'] ?? 'Weather Alert';

          // Infer type and extract category/EF scale
          String type = 'weather';
          int? category;
          int? efScale;
          final lowerEvent = eventType.toLowerCase();

          if (lowerEvent.contains('tornado')) {
            type = 'tornado';
            // Try to extract EF scale from title
            final efMatch = RegExp(r'ef(\d)').firstMatch(lowerEvent);
            if (efMatch != null) {
              efScale = int.tryParse(efMatch.group(1) ?? '');
            } else {
              efScale = severity == 'Extreme' ? 3 : 1;
            }
          } else if (lowerEvent.contains('hurricane') ||
              lowerEvent.contains('tropical')) {
            type = 'hurricane';
            // Try to extract category
            final catMatch = RegExp(r'category\s*(\d)').firstMatch(lowerEvent);
            if (catMatch != null) {
              category = int.tryParse(catMatch.group(1) ?? '');
            } else {
              category = severity == 'Extreme' ? 4 : 2;
            }
          } else if (lowerEvent.contains('flood') ||
              lowerEvent.contains('hydrologic')) {
            type = 'flood';
          } else if (lowerEvent.contains('fire')) {
            type = 'fire';
          } else if (lowerEvent.contains('wind')) {
            type = 'cyclone';
          }

          events.add(
            DisasterEvent(
              id: props['id'] ?? 'noaa_${events.length}',
              type: type,
              title: eventType,
              description: props['headline'] ?? eventType,
              severity: severity == 'Extreme'
                  ? 'Extreme'
                  : (severity == 'Severe' ? 'High' : 'Medium'),
              time: time,
              latitude: lat,
              longitude: lon,
              sourceUrl: props['web'],
              category: category,
              efScale: efScale,
            ),
          );
        }
      }
      developer.log('NOAA: Fetched ${events.length} alerts');
    } catch (e) {
      developer.log('Error fetching NOAA: $e');
    }
    return events;
  }

  // ==================
  // GDACS RSS
  // ==================
  Future<List<DisasterEvent>> _fetchGdacs() async {
    final List<DisasterEvent> events = [];
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(ApiConfig.gdacsRssUrl));
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final document = XmlDocument.parse(body);
        final items = document.findAllElements('item');

        for (var item in items) {
          final title =
              item.findElements('title').firstOrNull?.innerText ?? 'Unknown';
          final description =
              item.findElements('description').firstOrNull?.innerText ?? '';
          final link = item.findElements('link').firstOrNull?.innerText;
          final pubDate = item.findElements('pubDate').firstOrNull?.innerText;

          // Parse coordinates from geo namespace
          final latStr = item.findElements('geo:lat').firstOrNull?.innerText;
          final lonStr = item.findElements('geo:long').firstOrNull?.innerText;

          if (latStr == null || lonStr == null) continue;

          final lat = double.tryParse(latStr);
          final lon = double.tryParse(lonStr);
          if (lat == null || lon == null) continue;

          // Parse time
          DateTime? time;
          if (pubDate != null) {
            time = _parseRfc822Date(pubDate);
          }
          time ??= DateTime.now();
          if (DateTime.now().difference(time).inHours > 24) continue;

          // Infer type from title
          String type = 'weather';
          double? magnitude;
          final lowerTitle = title.toLowerCase();

          if (lowerTitle.contains('earthquake')) {
            type = 'earthquake';
            // Extract magnitude: "M 6.2 - ..."
            final magMatch = RegExp(r'm\s*(\d+\.?\d*)').firstMatch(lowerTitle);
            if (magMatch != null) {
              magnitude = double.tryParse(magMatch.group(1) ?? '');
            }
          } else if (lowerTitle.contains('flood')) {
            type = 'flood';
          } else if (lowerTitle.contains('cyclone') ||
              lowerTitle.contains('hurricane') ||
              lowerTitle.contains('typhoon')) {
            type = 'hurricane';
          } else if (lowerTitle.contains('volcano')) {
            type = 'volcano';
          } else if (lowerTitle.contains('drought')) {
            type = 'weather';
          }

          // Infer severity from GDACS alert level in description
          String severity = 'Medium';
          if (description.contains('Red') || description.contains('HIGH')) {
            severity = 'High';
          } else if (description.contains('Orange') ||
              description.contains('MEDIUM')) {
            severity = 'Medium';
          } else if (description.contains('Green') ||
              description.contains('LOW')) {
            severity = 'Low';
          }

          events.add(
            DisasterEvent(
              id: 'gdacs_${lat}_${lon}_${time.millisecondsSinceEpoch}',
              type: type,
              title: title,
              description: description,
              severity: severity,
              time: time,
              latitude: lat,
              longitude: lon,
              sourceUrl: link,
              magnitude: magnitude,
            ),
          );
        }
      }
      developer.log('GDACS: Fetched ${events.length} events');
    } catch (e) {
      developer.log('Error fetching GDACS: $e');
    }
    return events;
  }

  DateTime? _parseRfc822Date(String dateStr) {
    // RFC 822 format: "Thu, 09 Jan 2026 10:30:00 GMT"
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      // Try manual parsing
      final months = {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'aug': 8,
        'sep': 9,
        'oct': 10,
        'nov': 11,
        'dec': 12,
      };
      final parts = dateStr.split(RegExp(r'[\s,]+'));
      if (parts.length >= 5) {
        final day = int.tryParse(parts[1]);
        final month = months[parts[2].toLowerCase()];
        final year = int.tryParse(parts[3]);
        final timeParts = parts[4].split(':');
        if (day != null &&
            month != null &&
            year != null &&
            timeParts.length >= 2) {
          return DateTime(
            year,
            month,
            day,
            int.tryParse(timeParts[0]) ?? 0,
            int.tryParse(timeParts[1]) ?? 0,
            timeParts.length > 2 ? (int.tryParse(timeParts[2]) ?? 0) : 0,
          );
        }
      }
    }
    return null;
  }

  // ==================
  // Caching
  // ==================
  Future<void> _saveEventsToCache(List<DisasterEvent> events) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = events.map((e) => e.toJson()).toList();
      await prefs.setString(_cacheKey, jsonEncode(json));
      await prefs.setInt(
        _cacheTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      developer.log('Cached ${events.length} disaster events');
    } catch (e) {
      developer.log('Error saving cache: $e');
    }
  }

  Future<List<DisasterEvent>> _loadCachedEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached == null) return [];

      final timestamp = prefs.getInt(_cacheTimestampKey) ?? 0;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(timestamp),
      );

      // Clear if >24 hours old
      if (age.inHours >= 24) {
        await prefs.remove(_cacheKey);
        await prefs.remove(_cacheTimestampKey);
        developer.log('Cache expired, cleared');
        return [];
      }

      final list = (jsonDecode(cached) as List)
          .map((e) => DisasterEvent.fromJson(e as Map<String, dynamic>))
          .toList();
      developer.log('Loaded ${list.length} events from cache');
      return list;
    } catch (e) {
      developer.log('Error loading cache: $e');
      return [];
    }
  }

  List<DisasterEvent> _mergeAndDedupe(
    List<DisasterEvent> cached,
    List<DisasterEvent> fresh,
  ) {
    final Map<String, DisasterEvent> map = {};
    for (final e in cached) {
      map[e.id] = e;
    }
    for (final e in fresh) {
      map[e.id] = e; // Fresh overwrites cached
    }
    return map.values.toList();
  }

  // ==================
  // Auto-Unlock SOS
  // ==================
  Future<void> _checkAutoUnlockSOS() async {
    // Stage 1: Check if any severe disaster in list meets threshold AND is nearby
    Position? userPos;
    try {
      userPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      // ignore, assuming safe if location unknown
    }

    final hasSevereDisaster = _activeEvents.any((e) {
      if (!e.meetsAutoUnlockThreshold) return false;
      if (userPos == null) return false; // Don't panic if location unknown

      final distKm = calculateDistance(
        userPos.latitude,
        userPos.longitude,
        e.latitude,
        e.longitude,
      );
      return distKm <= 200; // 200km proximity
    });

    if (hasSevereDisaster) {
      // Stage 2: Ping Google to confirm connectivity (rate limited)
      final now = DateTime.now();
      if (_lastGooglePing == null ||
          now.difference(_lastGooglePing!) >= _googlePingLimit) {
        _lastGooglePing = now;
        final googleReachable = await _pingGoogle();

        if (!googleReachable) {
          // Both checks passed: severe disaster AND no internet
          if (!_sosAutoUnlocked) {
            _sosAutoUnlocked = true;
            _sosUnlockController.add(true);
            developer.log(
              'SOS Auto-Unlocked: Severe disaster + no connectivity',
            );
          }
        } else {
          // Internet works, don't auto-unlock
          if (_sosAutoUnlocked) {
            _sosAutoUnlocked = false;
            _sosUnlockController.add(false);
          }
        }
      }
    } else {
      // No severe disaster, reset auto-unlock
      if (_sosAutoUnlocked) {
        _sosAutoUnlocked = false;
        _sosUnlockController.add(false);
      }
    }
  }

  Future<bool> _pingGoogle() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse(ApiConfig.googlePingUrl));
      final response = await request.close();
      return response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }

  Future<void> _updateAlertLevel() async {
    Position? userPos;
    try {
      userPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      // ignore
    }

    final hasExtreme = _activeEvents.any((e) {
      if (e.severity != 'Extreme' && !e.meetsAutoUnlockThreshold) return false;
      if (userPos == null) return false;
      return calculateDistance(
            userPos.latitude,
            userPos.longitude,
            e.latitude,
            e.longitude,
          ) <=
          200;
    });

    final hasHigh = _activeEvents.any((e) {
      if (e.severity != 'High') return false;
      if (userPos == null) return false;
      return calculateDistance(
            userPos.latitude,
            userPos.longitude,
            e.latitude,
            e.longitude,
          ) <=
          200;
    });

    AlertLevel newLevel;
    if (hasExtreme) {
      newLevel = AlertLevel.disaster;
    } else if (hasHigh) {
      newLevel = AlertLevel.warning;
    } else {
      newLevel = AlertLevel.peace;
    }

    if (newLevel != _currentLevel) {
      _currentLevel = newLevel;
      _levelController.add(_currentLevel);
    }
  }

  Future<void> refresh() => _fetchAllSources();

  /// Get events that meet auto-unlock thresholds
  List<DisasterEvent> get severeEvents =>
      _activeEvents.where((e) => e.meetsAutoUnlockThreshold).toList();

  /// Calculate distance between two lat/lon points in km
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0; // Earth radius in km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
}
