import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

/// Offline Map Service
/// customized tile downloader for region-based caching
class OfflineMapService {
  static OfflineMapService? _instance;

  OfflineMapService._();

  static OfflineMapService get instance {
    _instance ??= OfflineMapService._();
    return _instance!;
  }

  bool _isInitialized = false;
  String? _tilesDir;

  /// Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      _tilesDir = path.join(appDocDir.path, 'tiles');
      await Directory(_tilesDir!).create(recursive: true);
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to init OfflineMapService: $e');
    }
  }

  /// Get storage statistics
  Future<Map<String, dynamic>> getStorageStats() async {
    if (!_isInitialized) await initialize();
    int count = 0;
    int sizeBytes = 0;

    try {
      final dir = Directory(_tilesDir!);
      if (await dir.exists()) {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            count++;
            sizeBytes += await entity.length();
          }
        }
      }
    } catch (_) {}

    return {'tiles': count, 'sizeBytes': sizeBytes};
  }

  /// Clear cache
  Future<void> clearCache() async {
    if (!_isInitialized) await initialize();
    try {
      final dir = Directory(_tilesDir!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(); // Recreate empty
      }
    } catch (e) {
      debugPrint('Failed to clear cache: $e');
    }
  }

  /// Get tile X index
  int _getTileX(double lon, int zoom) {
    return ((lon + 180) / 360 * (1 << zoom)).floor();
  }

  /// Get tile Y index
  int _getTileY(double lat, int zoom) {
    var latRad = lat * pi / 180;
    var n = 1 << zoom;
    // Use log for asinh polyfill: asinh(x) = log(x + sqrt(x^2 + 1))
    final tanLat = tan(latRad);
    final asinhVal = log(tanLat + sqrt(tanLat * tanLat + 1));
    return ((1.0 - asinhVal / pi) / 2.0 * n).floor();
  }

  /// Estimate number of tiles
  int estimateTileCount({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) {
    int count = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final x1 = _getTileX(bounds.west, z);
      final x2 = _getTileX(bounds.east, z);
      final y1 = _getTileY(bounds.north, z);
      final y2 = _getTileY(bounds.south, z);

      final cols = (x2 - x1).abs() + 1;
      final rows = (y2 - y1).abs() + 1;
      count += cols * rows;
    }
    return count;
  }

  /// Download region
  Future<void> downloadRegion({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required String
    tileUrlTemplate, // e.g. https://tile.openstreetmap.org/{z}/{x}/{y}.png
    required Function(int downloaded, int total) onProgress,
    required Function() onComplete,
    required Function(String error) onError,
  }) async {
    if (!_isInitialized) await initialize();

    // Calculate list of tiles
    []; // Point(x, y, z) - storing z in "mag" or separate struct
    // Actually simpler to store a struct
    List<_TileId> tileIds = [];

    for (var z = minZoom; z <= maxZoom; z++) {
      final x1 = _getTileX(bounds.west, z);
      final x2 = _getTileX(bounds.east, z);
      final y1 = _getTileY(bounds.north, z);
      final y2 = _getTileY(bounds.south, z);

      final minX = min(x1, x2);
      final maxX = max(x1, x2);
      final minY = min(y1, y2);
      final maxY = max(y1, y2);

      for (var x = minX; x <= maxX; x++) {
        for (var y = minY; y <= maxY; y++) {
          tileIds.add(_TileId(x: x, y: y, z: z));
        }
      }
    }

    final total = tileIds.length;
    int downloaded = 0;
    final client = HttpClient();

    // 2. Download loop (throttled/parallel)
    // Simple serial for robustness first, or small batches
    for (final tile in tileIds) {
      try {
        final savePath = path.join(
          _tilesDir!,
          '${tile.z}',
          '${tile.x}',
          '${tile.y}.png',
        );
        final file = File(savePath);

        if (await file.exists()) {
          downloaded++;
          onProgress(downloaded, total);
          continue; // Skip existing
        }

        await file.create(recursive: true);

        final url = tileUrlTemplate
            .replaceAll('{z}', '${tile.z}')
            .replaceAll('{x}', '${tile.x}')
            .replaceAll('{y}', '${tile.y}');

        final request = await client.getUrl(Uri.parse(url));
        // Add User Agent as required by OSM
        request.headers.add(
          'User-Agent',
          'MeshSOS_App/1.0 (flutter_project_hackathone)',
        );

        final response = await request.close();
        if (response.statusCode == 200) {
          await response.pipe(file.openWrite());
          downloaded++;
          onProgress(downloaded, total);
        } else {
          // Delete empty file if created
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error downloading tile $tile: $e');
        // Continues
      }
      // Small delay to be nice to OSM
      await Future.delayed(const Duration(milliseconds: 50));
    }

    client.close();
    onComplete();
  }
}

class _TileId {
  final int x;
  final int y;
  final int z;
  _TileId({required this.x, required this.y, required this.z});

  @override
  String toString() => '$z/$x/$y';
}
