import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../config/api_config.dart';
import '../services/offline_map_service.dart';

class RegionSelectionPage extends StatefulWidget {
  const RegionSelectionPage({super.key});

  @override
  State<RegionSelectionPage> createState() => _RegionSelectionPageState();
}

class _RegionSelectionPageState extends State<RegionSelectionPage> {
  final MapController _mapController = MapController();
  bool _isLoading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _moveToCurrentLocation();
  }

  Future<void> _moveToCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      _mapController.move(LatLng(pos.latitude, pos.longitude), 10);
    } catch (_) {}
  }

  Future<void> _downloadCurrentRegion() async {
    final bounds = _mapController.camera.visibleBounds;

    // Zoom levels to download. Typically 12-14 takes reasonable space.
    // 15-16 gets very large.
    final currentZoom = _mapController.camera.zoom;
    final minZoom = currentZoom.floor().clamp(10, 16);
    final maxZoom = (minZoom + 2).clamp(10, 16); // Download 2 zoom levels deep

    // Estimate size
    final tileCount = OfflineMapService.instance.estimateTileCount(
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
    // Approx 15KB per tile
    final estSizeMB = (tileCount * 0.015).toStringAsFixed(1);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Region?'),
        content: Text(
          'Download tiles for the visible area?\n'
          'Zoom Levels: $minZoom - $maxZoom\n'
          'Estimated Size: ~$estSizeMB MB\n'
          'This may take large storage space.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Starting download...';
      _downloadProgress = 0.0;
    });

    try {
      await OfflineMapService.instance.downloadRegion(
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        tileUrlTemplate: ApiConfig.osmTileUrl,
        onProgress: (downloaded, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = downloaded / total;
              _statusMessage = 'Downloading: $downloaded / $total tiles';
            });
          }
        },
        onComplete: () {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _statusMessage = 'Download Complete!';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Offline map saved successfully')),
            );
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _statusMessage = 'Error: $e';
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Offline Region')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(37.7749, -122.4194), // SF Default
              initialZoom: 10,
              minZoom: 5,
              maxZoom: 18,
            ),
            children: [
              TileLayer(urlTemplate: ApiConfig.osmTileUrl),
              // Show a border for the "downloadable" area roughly?
              // Or just relying on viewport.
            ],
          ),

          if (_isLoading)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(_statusMessage),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: _downloadProgress),
                    ],
                  ),
                ),
              ),
            )
          else
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: ElevatedButton.icon(
                onPressed: _downloadCurrentRegion,
                icon: const Icon(Icons.download),
                label: const Text('Download Visible Region'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
