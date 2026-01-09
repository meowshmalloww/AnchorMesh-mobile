import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/sos_packet.dart';
import '../models/sos_status.dart';
import '../services/ble_service.dart';
import '../config/api_config.dart';

/// Map page with SOS heatmap visualization
/// Supports 3 zoom levels:
/// - City View: Large circles with counts
/// - Street View: Medium circles, more detail
/// - Close Up: Individual dots per person
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  final BLEService _bleService = BLEService.instance;

  List<SOSPacket> _packets = [];
  double _currentZoom = 13.0;
  StreamSubscription? _packetSubscription;

  // Zoom thresholds for view modes
  static const double cityViewZoom = 10.0;
  static const double streetViewZoom = 14.0;

  @override
  void initState() {
    super.initState();
    _loadPackets();
    _setupListener();
  }

  Future<void> _loadPackets() async {
    final packets = await _bleService.getActivePackets();
    if (mounted) {
      setState(() => _packets = packets);
      _centerOnPackets();
    }
  }

  void _setupListener() {
    _packetSubscription = _bleService.onPacketReceived.listen((packet) {
      if (mounted) {
        setState(() {
          final idx = _packets.indexWhere((p) => p.userId == packet.userId);
          if (idx >= 0) {
            _packets[idx] = packet;
          } else {
            _packets.add(packet);
          }
        });
      }
    });
  }

  void _centerOnPackets() {
    if (_packets.isEmpty) return;

    final lats = _packets.map((p) => p.latitude).toList();
    final lons = _packets.map((p) => p.longitude).toList();

    final centerLat = (lats.reduce((a, b) => a + b)) / lats.length;
    final centerLon = (lons.reduce((a, b) => a + b)) / lons.length;

    _mapController.move(LatLng(centerLat, centerLon), _currentZoom);
  }

  @override
  void dispose() {
    _packetSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SOS Map"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadPackets),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _centerOnPackets,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(37.7749, -122.4194),
              initialZoom: ApiConfig.defaultMapZoom,
              minZoom: ApiConfig.minMapZoom,
              maxZoom: ApiConfig.maxMapZoom,
              onPositionChanged: (position, hasGesture) {
                setState(() => _currentZoom = position.zoom);
              },
            ),
            children: [
              // Tile layer (OSM by default - FREE, MapTiler optional)
              TileLayer(
                urlTemplate: ApiConfig.hasMapTiler
                    ? ApiConfig.mapTilerStreetsUrl
                    : ApiConfig.osmTileUrl,
                userAgentPackageName: 'com.development.heyblue',
                maxZoom: ApiConfig.maxMapZoom,
              ),
              // Markers layer
              MarkerLayer(markers: _buildMarkers()),
              // Heatmap circles (for city/street view)
              if (_currentZoom < streetViewZoom)
                CircleLayer(circles: _buildHeatmapCircles()),
            ],
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    // Only show individual markers in close-up view
    if (_currentZoom < streetViewZoom) return [];

    return _packets.map((packet) {
      final color = Color(packet.status.colorValue);
      return Marker(
        point: LatLng(packet.latitude, packet.longitude),
        width: 40,
        height: 50,
        child: GestureDetector(
          onTap: () => _showPacketDetails(packet),
          child: Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(color: color.withAlpha(100), blurRadius: 8),
                  ],
                ),
                child: Icon(packet.status.icon, color: Colors.white, size: 16),
              ),
              Container(width: 2, height: 10, color: color),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<CircleMarker> _buildHeatmapCircles() {
    if (_packets.isEmpty) return [];

    // Group packets by approximate location (grid cells)
    final gridSize = _currentZoom < cityViewZoom ? 0.1 : 0.02; // degrees
    final groups = <String, List<SOSPacket>>{};

    for (final packet in _packets) {
      final gridLat = (packet.latitude / gridSize).floor() * gridSize;
      final gridLon = (packet.longitude / gridSize).floor() * gridSize;
      final key = '$gridLat,$gridLon';
      groups.putIfAbsent(key, () => []).add(packet);
    }

    return groups.entries.map((entry) {
      final packets = entry.value;
      final centerLat =
          packets.map((p) => p.latitude).reduce((a, b) => a + b) /
          packets.length;
      final centerLon =
          packets.map((p) => p.longitude).reduce((a, b) => a + b) /
          packets.length;

      // Color based on most urgent status in group
      final urgentStatus = packets.map((p) => p.status).reduce((a, b) {
        if (a == SOSStatus.sos || b == SOSStatus.sos) {
          return SOSStatus.sos;
        }
        if (a == SOSStatus.medical || b == SOSStatus.medical) {
          return SOSStatus.medical;
        }
        if (a == SOSStatus.trapped || b == SOSStatus.trapped) {
          return SOSStatus.trapped;
        }
        if (a == SOSStatus.supplies || b == SOSStatus.supplies) {
          return SOSStatus.supplies;
        }
        return SOSStatus.safe;
      });

      final color = Color(urgentStatus.colorValue);
      final radius = _currentZoom < cityViewZoom
          ? 30.0 + (packets.length * 5).clamp(0, 50).toDouble()
          : 15.0 + (packets.length * 3).clamp(0, 30).toDouble();

      return CircleMarker(
        point: LatLng(centerLat, centerLon),
        radius: radius,
        color: color.withAlpha(100),
        borderColor: color,
        borderStrokeWidth: 2,
      );
    }).toList();
  }

  void _showPacketDetails(SOSPacket packet) {
    final color = Color(packet.status.colorValue);
    final ageMinutes = packet.ageSeconds ~/ 60;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(packet.status.icon, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              packet.status.description,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${packet.latitude.toStringAsFixed(5)}, ${packet.longitude.toStringAsFixed(5)}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              '$ageMinutes minutes ago',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _mapController.move(
                        LatLng(packet.latitude, packet.longitude),
                        16.0,
                      );
                    },
                    icon: const Icon(Icons.zoom_in),
                    label: const Text('Zoom In'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
