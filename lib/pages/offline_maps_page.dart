import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/offline_map_service.dart';
import '../config/api_config.dart';
import 'package:latlong2/latlong.dart';

/// Offline Maps settings page
/// Allows users to download and manage offline map tiles
class OfflineMapsPage extends StatefulWidget {
  const OfflineMapsPage({super.key});

  @override
  State<OfflineMapsPage> createState() => _OfflineMapsPageState();
}

class _OfflineMapsPageState extends State<OfflineMapsPage> {
  final OfflineMapService _mapService = OfflineMapService.instance;

  bool _isInitialized = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  int _downloadedTiles = 0;
  int _totalTiles = 0;

  double _radiusKm = 10;
  int _maxZoom = 16;
  double _estimatedSizeMb = 0;

  LatLng? _currentLocation;
  Map<String, dynamic> _storageStats = {'tiles': 0, 'sizeBytes': 0};

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _mapService.initialize();
    await _loadStats();
    await _getCurrentLocation();
    setState(() => _isInitialized = true);
  }

  Future<void> _loadStats() async {
    final stats = await _mapService.getStorageStats();
    setState(() => _storageStats = stats);
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
      _updateEstimate();
    } catch (e) {
      // Default to San Francisco
      setState(() {
        _currentLocation = const LatLng(37.7749, -122.4194);
      });
      _updateEstimate();
    }
  }

  void _updateEstimate() {
    final estimate = _mapService.estimateDownloadSize(
      radiusKm: _radiusKm,
      minZoom: 10,
      maxZoom: _maxZoom,
    );
    setState(() => _estimatedSizeMb = estimate);
  }

  Future<void> _startDownload() async {
    if (_currentLocation == null) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadedTiles = 0;
    });

    final tileUrl = ApiConfig.hasMapTiler
        ? ApiConfig.mapTilerStreetsUrl
        : ApiConfig.osmTileUrl;

    await _mapService.downloadRegion(
      center: _currentLocation!,
      radiusKm: _radiusKm,
      minZoom: 10,
      maxZoom: _maxZoom,
      tileUrl: tileUrl,
      onProgress: (downloaded, total) {
        if (mounted) {
          setState(() {
            _downloadedTiles = downloaded;
            _totalTiles = total;
            _downloadProgress = total > 0 ? downloaded / total : 0;
          });
        }
      },
      onComplete: () async {
        await _loadStats();
        if (mounted) {
          setState(() => _isDownloading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Map download complete!')),
          );
        }
      },
    );
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear offline maps?'),
        content: const Text('This will delete all cached map tiles.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _mapService.clearCache();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cache cleared')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cachedMb = (_storageStats['sizeBytes'] ?? 0) / (1024 * 1024);

    return Scaffold(
      appBar: AppBar(title: const Text('Offline Maps')),
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Current cache info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.storage, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cached Maps',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${_storageStats['tiles']} tiles (${cachedMb.toStringAsFixed(1)} MB)',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _storageStats['tiles'] > 0
                            ? _clearCache
                            : null,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Download options
                const Text(
                  'DOWNLOAD NEW AREA',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),

                // Location
                ListTile(
                  leading: const Icon(Icons.location_on),
                  title: const Text('Center Location'),
                  subtitle: _currentLocation != null
                      ? Text(
                          '${_currentLocation!.latitude.toStringAsFixed(4)}, ${_currentLocation!.longitude.toStringAsFixed(4)}',
                        )
                      : const Text('Fetching...'),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _getCurrentLocation,
                  ),
                ),

                // Radius slider
                ListTile(
                  leading: const Icon(Icons.radar),
                  title: Text('Radius: ${_radiusKm.toStringAsFixed(0)} km'),
                  subtitle: Slider(
                    value: _radiusKm,
                    min: 5,
                    max: 50,
                    divisions: 9,
                    label: '${_radiusKm.toStringAsFixed(0)} km',
                    onChanged: (value) {
                      setState(() => _radiusKm = value);
                      _updateEstimate();
                    },
                  ),
                ),

                // Zoom level
                ListTile(
                  leading: const Icon(Icons.zoom_in),
                  title: Text('Max zoom: $_maxZoom'),
                  subtitle: Slider(
                    value: _maxZoom.toDouble(),
                    min: 12,
                    max: 18,
                    divisions: 6,
                    label: '$_maxZoom',
                    onChanged: (value) {
                      setState(() => _maxZoom = value.round());
                      _updateEstimate();
                    },
                  ),
                ),

                // Estimate
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Estimated size: ${_estimatedSizeMb.toStringAsFixed(1)} MB',
                        style: const TextStyle(color: Colors.blue),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Download button / progress
                if (_isDownloading) ...[
                  Column(
                    children: [
                      LinearProgressIndicator(value: _downloadProgress),
                      const SizedBox(height: 8),
                      Text(
                        'Downloading: $_downloadedTiles / $_totalTiles tiles',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: _currentLocation != null ? _startDownload : null,
                    icon: const Icon(Icons.download),
                    label: const Text('Download Map Tiles'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],

                const SizedBox(height: 30),

                // Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.warning_amber,
                            color: Colors.orange,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Offline Maps Info',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Download maps before a disaster strikes\n'
                        '• Higher zoom = more detail = larger download\n'
                        '• Maps work without internet connection',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
