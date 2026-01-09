/// API Configuration for Mesh SOS App
/// IMPORTANT: API usage is strictly rate-limited to conserve quotas
library;

class ApiConfig {
  // ========================================
  // ☁️ SUPABASE (Cloud Sync)
  // ========================================

  /// Supabase Project URL
  static const String supabaseUrl = 'https://iiompuquacigtguvizfa.supabase.co';

  /// Supabase Anonymous Key (safe to expose - RLS protects data)
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlpb21wdXF1YWNpZ3RndXZpemZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc4NDMwMTMsImV4cCI6MjA4MzQxOTAxM30.Ml2JbvYVmMDur1lr5gT81Uathm5VwUEQFWhuZExsdoo';

  /// How often to attempt cloud sync (seconds)
  static const int syncIntervalSeconds = 300; // 5 minutes

  // ========================================
  // 🗺️ MAP TILES
  // ========================================

  /// MapTiler API Key (DISABLED by default to save quota)
  /// Set useMapTiler = true to enable
  static const String mapTilerApiKey = ''; // !MapTIler APi Key

  /// IMPORTANT: Set to false to use free OSM tiles
  /// Each map view = 15-30 tile requests! Set to true only for demos
  static const bool useMapTiler = false;

  /// MapTiler tile URL (streets style)
  static String get mapTilerStreetsUrl =>
      'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=$mapTilerApiKey';

  /// OpenStreetMap (FREE - unlimited, no key needed)
  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Check if MapTiler should be used (key exists AND enabled)
  static bool get hasMapTiler => mapTilerApiKey.isNotEmpty && useMapTiler;

  // ========================================
  // 🗺️ MAP LIMITS (to conserve requests)
  // ========================================

  /// Maximum zoom level (higher = more tiles = more requests)
  /// Zoom 15 = ~25 tiles, Zoom 18 = ~400+ tiles
  static const double maxMapZoom = 15.0;

  /// Minimum zoom level
  static const double minMapZoom = 8.0;

  /// Default zoom level for viewing
  static const double defaultMapZoom = 12.0;

  // ========================================
  // 🌍 DISASTER APIS (FREE - No key needed!)
  // ========================================

  /// USGS Earthquake API
  /// FREE - No API key required
  /// Rate limit: App enforces 1 request per 60 minutes (was 15)
  static const String usgsEarthquakeApi =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/significant_hour.geojson';

  /// USGS all earthquakes (for global view)
  static const String usgsAllEarthquakesApi =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.geojson';

  /// NOAA Weather Alerts API
  /// FREE - No API key required
  /// Rate limit: App enforces 1 request per 60 minutes (was 30)
  static const String noaaAlertsApi = 'https://api.weather.gov/alerts/active';

  // ========================================
  // ⚙️ RATE LIMITS (STRICT!)
  // ========================================

  /// Minimum earthquake magnitude to trigger alert
  static const double minEarthquakeMagnitude = 6.0;

  /// How often to check USGS (minutes) - INCREASED to save quota
  static const int usgsCheckIntervalMinutes = 60;

  /// How often to check NOAA (minutes) - INCREASED to save quota
  static const int noaaCheckIntervalMinutes = 60;

  /// Background check interval (minutes)
  static const int backgroundCheckIntervalMinutes = 60;
}
