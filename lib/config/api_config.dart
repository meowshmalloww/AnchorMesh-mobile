/// Secure API Configuration
///
/// ⚠️ THIS FILE CONTAINS SENSITIVE API KEYS
/// ⚠️ DO NOT COMMIT TO VERSION CONTROL
///
/// To configure:
/// 1. Get API keys from respective services
/// 2. Replace placeholder values below
/// 3. Keep this file in .gitignore
class ApiConfig {
  ApiConfig._();

  // ==================
  // Map Services
  // ==================

  /// MapTiler API Key - Get at https://www.maptiler.com/
  static const String mapTilerApiKey = '';

  /// OSM Tile URL (free, no key needed)
  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// MapTiler tile URLs
  static String get mapTilerStreetsUrl =>
      'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$mapTilerApiKey';

  static String get mapTilerSatelliteUrl =>
      'https://api.maptiler.com/maps/satellite/{z}/{x}/{y}.jpg?key=$mapTilerApiKey';

  // ==================
  // Disaster APIs (Free)
  // ==================

  static const String usgsEarthquakeApi =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/significant_hour.geojson';

  static const String usgsAllEarthquakesApi =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson';

  static const String noaaWeatherAlertsApi =
      'https://api.weather.gov/alerts/active';

  // ==================
  // Backend (Optional)
  // ==================

  static const String backendBaseUrl = '';
  static const String backendApiKey = '';

  static String get sosUploadEndpoint => '$backendBaseUrl/api/sos';
  static String get sosDownloadEndpoint => '$backendBaseUrl/api/commands';

  // ==================
  // Helpers
  // ==================

  static bool get hasMapTiler => mapTilerApiKey.isNotEmpty;
  static bool get hasBackend => backendBaseUrl.isNotEmpty;
}
