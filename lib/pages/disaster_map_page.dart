import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/disaster_event.dart';
import '../services/disaster_service.dart';

class DisasterMapPage extends StatefulWidget {
  const DisasterMapPage({super.key});

  @override
  State<DisasterMapPage> createState() => _DisasterMapPageState();
}

class _DisasterMapPageState extends State<DisasterMapPage>
    with AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  final DisasterService _disasterService = DisasterService.instance;

  // Zoom tracking for dynamic marker sizing
  final ValueNotifier<double> _zoomNotifier = ValueNotifier(2.0);

  List<DisasterEvent> _events = [];
  StreamSubscription? _eventSub;
  bool _isLoading = false;

  @override
  bool get wantKeepAlive => true; // Keep map state alive

  @override
  void initState() {
    super.initState();
    _events = _disasterService.activeEvents;
    _setupListener();
    if (_events.isEmpty) {
      _fetchData();
    }
  }

  void _setupListener() {
    _eventSub = _disasterService.eventsStream.listen((events) {
      if (mounted) {
        setState(() => _events = events);
      }
    });
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    await _disasterService.refresh();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _zoomNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      appBar: AppBar(
        title: const Text('Disaster Map'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (!_isLoading)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData),
        ],
      ),
      body: Stack(
        children: [
          // Map layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(20, 0),
              initialZoom: 2.0,
              minZoom: 2.0,
              maxZoom: 18.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: (position, hasGesture) {
                // Update zoom notifier for reactive marker sizing
                _zoomNotifier.value = position.zoom;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.development.heyblue',
                maxZoom: 18,
              ),
              // Zoom-reactive markers
              ValueListenableBuilder<double>(
                valueListenable: _zoomNotifier,
                builder: (context, zoom, _) {
                  return MarkerLayer(markers: _buildMarkers(zoom));
                },
              ),
            ],
          ),

          // Event list overlay
          DraggableScrollableSheet(
            initialChildSize: 0.3,
            minChildSize: 0.1,
            maxChildSize: 0.7,
            snap: true,
            snapSizes: const [0.1, 0.3, 0.7],
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(30),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.public,
                            size: 20,
                            color: Colors.brown,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Earthquakes (${_events.length})",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // List
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _events.length,
                        itemBuilder: (context, index) {
                          final event = _events[index];
                          final style = _getDisasterStyle(event.type);
                          final timeStr = _formatTime(event.time);

                          return ListTile(
                            leading: Icon(
                              style.icon,
                              color: style.color,
                              size: 24,
                            ),
                            title: Text(
                              event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              "${event.description} • $timeStr",
                              style: const TextStyle(fontSize: 12),
                            ),
                            dense: true,
                            onTap: () {
                              _mapController.move(
                                LatLng(event.latitude, event.longitude),
                                8.0,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers(double zoom) {
    // Dynamic marker sizing based on zoom level
    // At zoom 2 (world view): tiny dots (6px)
    // At zoom 10+: full size markers (40px)
    final double markerSize = (6 + (zoom * 3.5)).clamp(6.0, 40.0);
    final double iconSize = (markerSize * 0.6).clamp(4.0, 24.0);

    return _events.map((event) {
      final style = _getDisasterStyle(event.type);
      final severityColor = _getSeverityColor(event.severity);

      return Marker(
        point: LatLng(event.latitude, event.longitude),
        width: markerSize,
        height: markerSize,
        child: GestureDetector(
          onTap: () => _showEventDetails(event, style, severityColor),
          child: Container(
            decoration: BoxDecoration(
              color: style.color.withAlpha(200),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: zoom > 5 ? 2 : 1),
              boxShadow: zoom > 4
                  ? [
                      BoxShadow(
                        color: severityColor.withAlpha(128),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: zoom > 4
                ? Icon(style.icon, color: Colors.white, size: iconSize)
                : null, // No icon at very low zoom for clarity
          ),
        ),
      );
    }).toList();
  }

  void _showEventDetails(
    DisasterEvent event,
    _DisasterStyle style,
    Color severityColor,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: style.color.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(style.icon, color: style.color, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        event.type.toUpperCase(),
                        style: TextStyle(
                          color: style.color,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(event.description),
            const SizedBox(height: 20),
            Row(
              children: [
                _buildDetailChip(Icons.access_time, _formatTime(event.time)),
                const SizedBox(width: 12),
                _buildDetailChip(
                  Icons.warning_amber,
                  event.severity,
                  color: severityColor,
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (event.sourceUrl != null)
              const Text(
                'Source: USGS/NOAA APIs',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (color ?? Colors.grey).withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color ?? Colors.grey[700]),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color ?? Colors.grey[800],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    // Simple formatter, can be improved
    return "${time.hour}:${time.minute.toString().padLeft(2, '0')}";
  }

  _DisasterStyle _getDisasterStyle(String type) {
    switch (type.toLowerCase()) {
      case 'earthquake':
        return _DisasterStyle(Icons.public, Colors.brown);
      case 'flood':
        return _DisasterStyle(Icons.water, Colors.blue);
      case 'hurricane':
      case 'cyclone':
        return _DisasterStyle(Icons.storm, Colors.deepPurple);
      case 'tornado':
        return _DisasterStyle(Icons.tornado, Colors.grey);
      case 'wildfire':
      case 'fire':
        return _DisasterStyle(Icons.local_fire_department, Colors.orange);
      case 'volcano':
        return _DisasterStyle(Icons.volcano, Colors.red);
      case 'tsunami':
        return _DisasterStyle(Icons.tsunami, Colors.teal);
      case 'weather':
        return _DisasterStyle(Icons.thunderstorm, Colors.indigo);
      default:
        return _DisasterStyle(Icons.warning, Colors.amber);
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'extreme':
        return Colors.red;
      case 'high':
        return Colors.deepOrange;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }
}

class _DisasterStyle {
  final IconData icon;
  final Color color;
  const _DisasterStyle(this.icon, this.color);
}
