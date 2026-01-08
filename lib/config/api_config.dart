/// API Configuration for Mesh SOS App
library;

class ApiConfig {
  // ========================================
  // 🗺️ MAP TILES (Optional)
  // ========================================

  /// MapTiler API Key
  /// Get free at: https://www.maptiler.com/ (100k tiles/month free)
  /// Leave empty to use OpenStreetMap (works fine, just basic styling)
  static const String mapTilerApiKey = 'nrWM0WzSZUZacCx4JOVU';

  /// MapTiler tile URL (streets style)
  static String get mapTilerStreetsUrl =>
      'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=$mapTilerApiKey';

  /// OpenStreetMap fallback (free, no key needed)
  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Check if MapTiler is configured
  static bool get hasMapTiler => mapTilerApiKey.isNotEmpty;

  // ========================================
  // 🌍 DISASTER APIS (FREE - No key needed!)
  // ========================================

  /// USGS Earthquake API
  /// FREE - No API key required
  /// Rate limit: App enforces 1 request per 15 minutes
  /// Docs: https://earthquake.usgs.gov/fdsnws/event/1/
  static const String usgsEarthquakeApi =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/significant_hour.geojson';

  /// NOAA Weather Alerts API
  /// FREE - No API key required
  /// Rate limit: App enforces 1 request per 30 minutes
  /// Docs: https://www.weather.gov/documentation/services-web-api
  static const String noaaAlertsApi = 'https://api.weather.gov/alerts/active';

  // ========================================
  // ⚙️ APP SETTINGS
  // ========================================

  /// Minimum earthquake magnitude to trigger alert
  static const double minEarthquakeMagnitude = 6.0;

  /// How often to check USGS (minutes)
  /// Don't set below 15 - be respectful to free APIs!
  static const int usgsCheckIntervalMinutes = 30;

  /// How often to check NOAA (minutes)
  static const int noaaCheckIntervalMinutes = 30;
}
