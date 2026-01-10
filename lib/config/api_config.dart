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
  static const String mapTilerApiKey =
      'RTqHkOZyon4AG1STywyT'; // !MapTiler APi Key

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
  /// Zoom 18 = street-level detail
  static const double maxMapZoom = 18.0;

  /// Minimum zoom level (prevents global zoom out)
  /// Zoom 10 = city/region level
  static const double minMapZoom = 10.0;

  /// Default zoom level for viewing
  static const double defaultMapZoom = 13.0;

  // ========================================
  // 🌍 DISASTER APIS (FREE - No key needed!)
  // ========================================

  /// USGS Earthquake API (All earthquakes in last 24h)
  /// FREE - No API key required
  static const String usgsEarthquakeApi =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson';

  /// USGS significant earthquakes only (for quick checks)
  static const String usgsSignificantApi =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/significant_hour.geojson';

  /// NOAA Weather Alerts API (US only)
  /// FREE - No API key required
  static const String noaaAlertsApi =
      'https://api.weather.gov/alerts/active?severity=Severe,Extreme';

  /// GDACS Global Disaster Alert RSS Feed
  /// FREE - No API key required
  static const String gdacsRssUrl = 'https://www.gdacs.org/xml/rss.xml';

  /// Google connectivity check URL
  /// Used for stage-2 SOS auto-unlock verification
  static const String googlePingUrl = 'https://www.google.com/generate_204';

  // ========================================
  // ⚙️ RATE LIMITS
  // ========================================

  /// Minimum earthquake magnitude to trigger auto-unlock
  static const double minEarthquakeMagnitude = 6.0;

  /// Minimum hurricane category to trigger auto-unlock
  static const int minHurricaneCategory = 3;

  /// Minimum tornado EF scale to trigger auto-unlock
  static const int minTornadoEfScale = 2;

  /// How often to check each disaster API (minutes)
  static const int disasterCheckIntervalMinutes = 20;

  /// How often to ping Google for connectivity (minutes)
  static const int googlePingIntervalMinutes = 5;

  /// Cache expiry time (hours)
  static const int cacheExpiryHours = 24;
}
