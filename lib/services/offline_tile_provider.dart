import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'offline_map_service.dart';

/// A TileProvider that checks for local offline tiles first.
/// If a local tile exists, it is used. Otherwise, it falls back to the network.
class LocalFallbackTileProvider extends NetworkTileProvider {
  LocalFallbackTileProvider();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    // Check if we have a downloaded tile
    final path = OfflineMapService.instance.getTilePath(
      coordinates.z,
      coordinates.x,
      coordinates.y,
    );

    // Sync check is fast enough for UI on modern devices (flash storage)
    // If this causes jank, we'd need a more complex async ImageProvider,
    // but for this hackathon speed, sync check is standard for FileImage fallback.
    final file = File(path);
    if (file.existsSync()) {
      return FileImage(file);
    }

    // Fallback to standard network request
    // This uses the urlTemplate from TileLayer options
    return super.getImage(coordinates, options);
  }
}
