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

  // Selected event for danger zone display
  DisasterEvent? _selectedEvent;

  // Filters
  final Set<String> _selectedFilters = {'all'};
  final List<String> _filterOptions = [
    'all',
    'earthquake',
    'fire',
    'flood',
    'hurricane',
    'tornado',
    'weather',
    'volcano',
  ];

  List<DisasterEvent> get _filteredEvents {
    if (_selectedFilters.contains('all')) return _events;
    return _events.where((e) => _selectedFilters.contains(e.type)).toList();
  }

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
        setState(() {
          _events = events;
        });
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
          // Loading overlay (shows while fetching)
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Loading global disaster data...',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          // Map layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(20, 0), // World center
              initialZoom: 2.0, // Start global to show all alerts
              minZoom: 2.0, // Allow global view
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
              ValueListenableBuilder<double>(
                valueListenable: _zoomNotifier,
                builder: (context, zoom, _) {
                  return MarkerLayer(markers: _buildMarkers(zoom));
                },
              ),
              // Danger Zone Circle (when event selected)
              if (_selectedEvent != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(
                        _selectedEvent!.latitude,
                        _selectedEvent!.longitude,
                      ),
                      radius: _getDangerRadius(_selectedEvent!),
                      useRadiusInMeter: true,
                      color: Colors.red.withAlpha(50),
                      borderColor: Colors.red,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
            ],
          ),

          // Filter Bar
          Positioned(top: 10, left: 10, right: 10, child: _buildFilterBar()),

          // Event list overlay
          DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.1,
            maxChildSize: 0.9,
            snap: true,
            snapSizes: const [0.1, 0.4, 0.9],
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
                          Icon(
                            _getHeaderIcon(),
                            size: 20,
                            color: _getHeaderColor(),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "${_getHeaderTitle()} (${_filteredEvents.length})",
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
                        itemCount: _filteredEvents.length,
                        itemBuilder: (context, index) {
                          final event = _filteredEvents[index];
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

          // Zoom Control Buttons
          Positioned(
            right: 16,
            top: 60,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'disasterZoomIn',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  onPressed: () {
                    final newZoom = (_zoomNotifier.value + 1).clamp(2.0, 18.0);
                    _mapController.move(_mapController.camera.center, newZoom);
                  },
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'disasterZoomOut',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  onPressed: () {
                    final newZoom = (_zoomNotifier.value - 1).clamp(2.0, 18.0);
                    _mapController.move(_mapController.camera.center, newZoom);
                  },
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Dynamic header helpers based on filter selection
  String _getHeaderTitle() {
    if (_selectedFilters.contains('all') || _selectedFilters.length > 1) {
      return 'All Events';
    }
    final filter = _selectedFilters.first;
    switch (filter) {
      case 'earthquake':
        return 'Earthquakes';
      case 'fire':
        return 'Fires';
      case 'flood':
        return 'Floods';
      case 'hurricane':
        return 'Hurricanes';
      case 'tornado':
        return 'Tornadoes';
      case 'weather':
        return 'Weather Alerts';
      case 'volcano':
        return 'Volcanoes';
      default:
        return 'Events';
    }
  }

  IconData _getHeaderIcon() {
    if (_selectedFilters.contains('all') || _selectedFilters.length > 1) {
      return Icons.public;
    }
    final filter = _selectedFilters.first;
    switch (filter) {
      case 'earthquake':
        return Icons.public;
      case 'fire':
        return Icons.local_fire_department;
      case 'flood':
        return Icons.water;
      case 'hurricane':
        return Icons.cyclone;
      case 'tornado':
        return Icons.tornado;
      case 'weather':
        return Icons.cloud;
      case 'volcano':
        return Icons.volcano;
      default:
        return Icons.warning;
    }
  }

  Color _getHeaderColor() {
    if (_selectedFilters.contains('all') || _selectedFilters.length > 1) {
      return Colors.brown;
    }
    final filter = _selectedFilters.first;
    switch (filter) {
      case 'earthquake':
        return Colors.red;
      case 'fire':
        return Colors.red.shade900;
      case 'flood':
        return Colors.blue;
      case 'hurricane':
        return Colors.purple;
      case 'tornado':
        return Colors.grey;
      case 'weather':
        return Colors.orange;
      case 'volcano':
        return Colors.deepOrange;
      default:
        return Colors.brown;
    }
  }

  // Calculate danger radius in meters using realistic estimates
  // Sources: USGS, NOAA, FEMA typical impact zones
  double _getDangerRadius(DisasterEvent event) {
    switch (event.type.toLowerCase()) {
      case 'earthquake':
        // Realistic felt intensity radius based on magnitude
        // Mag 3: ~15km, Mag 4: ~30km, Mag 5: ~50km,
        // Mag 6: ~100km, Mag 7: ~150km, Mag 8+: ~300km
        final mag = event.magnitude ?? 4.0;
        if (mag < 3.0) return 10000.0; // 10km
        if (mag < 4.0) return 15000.0; // 15km
        if (mag < 5.0) return 30000.0; // 30km
        if (mag < 6.0) return 50000.0; // 50km
        if (mag < 7.0) return 100000.0; // 100km
        if (mag < 8.0) return 150000.0; // 150km
        return 300000.0; // 300km for 8+

      case 'hurricane':
        // Tropical storm wind radius (not just eye)
        // Cat 1: 50km, Cat 2: 70km, Cat 3: 100km, Cat 4: 130km, Cat 5: 160km
        final cat = event.category ?? 1;
        return [
          50000.0,
          70000.0,
          100000.0,
          130000.0,
          160000.0,
        ][cat.clamp(1, 5) - 1];

      case 'tornado':
        // Tornado damage path width (more realistic)
        // EF0: 50m, EF1: 100m, EF2: 250m, EF3: 500m, EF4: 1km, EF5: 2km
        final ef = event.efScale ?? 1;
        return [50.0, 100.0, 250.0, 500.0, 1000.0, 2000.0][ef.clamp(0, 5)];

      case 'fire':
      case 'wildfire':
        // Wildfire evacuation zone - varies greatly
        return _getSeverityRadius(event.severity, 3000.0); // 3km base

      case 'flood':
        // Flood zone - highly variable by terrain
        return _getSeverityRadius(event.severity, 5000.0); // 5km base

      case 'volcano':
        // Volcanic exclusion zone
        return _getSeverityRadius(event.severity, 10000.0); // 10km base

      default:
        return _getSeverityRadius(event.severity, 5000.0); // 5km default
    }
  }

  // Helper for severity-based radius scaling
  double _getSeverityRadius(String severity, double baseRadius) {
    switch (severity.toLowerCase()) {
      case 'extreme':
        return baseRadius * 2.5;
      case 'severe':
      case 'high':
        return baseRadius * 1.8;
      case 'moderate':
      case 'medium':
        return baseRadius * 1.2;
      case 'minor':
      case 'low':
        return baseRadius * 0.6;
      default:
        return baseRadius;
    }
  }

  List<Marker> _buildMarkers(double zoom) {
    // Dynamic marker sizing based on zoom level
    // At zoom 2 (world view): tiny dots (6px)
    // At zoom 10+: full size markers (40px)
    final double markerSize = (6 + (zoom * 3.5)).clamp(6.0, 40.0);
    final double iconSize = (markerSize * 0.6).clamp(4.0, 24.0);

    return _filteredEvents.map((event) {
      final style = _getDisasterStyle(event.type);
      final severityColor = _getSeverityColor(event.severity);

      return Marker(
        point: LatLng(event.latitude, event.longitude),
        width: markerSize,
        height: markerSize,
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedEvent = event);
            _showEventDetails(event, style, severityColor);
          },
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
        return _DisasterStyle(Icons.public, Colors.red); // User requested Red
      case 'flood':
        return _DisasterStyle(Icons.water, Colors.blue);
      case 'hurricane':
      case 'cyclone':
        return _DisasterStyle(Icons.storm, Colors.deepPurple);
      case 'tornado':
        return _DisasterStyle(Icons.tornado, Colors.grey);
      case 'wildfire':
      case 'fire':
        return _DisasterStyle(
          Icons.local_fire_department,
          const Color(0xFF8B0000),
        ); // Dark Red
      case 'volcano':
        return _DisasterStyle(Icons.volcano, Colors.deepOrange);
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
        return Colors.grey;
    }
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _filterOptions.map((filter) {
          final isSelected = _selectedFilters.contains(filter);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                filter == 'all'
                    ? 'All'
                    : filter[0].toUpperCase() + filter.substring(1),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontSize: 12,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (filter == 'all') {
                    _selectedFilters.clear();
                    _selectedFilters.add('all');
                  } else {
                    _selectedFilters.remove('all');
                    if (selected) {
                      _selectedFilters.add(filter);
                    } else {
                      _selectedFilters.remove(filter);
                      if (_selectedFilters.isEmpty) {
                        _selectedFilters.add('all');
                      }
                    }
                  }
                });
              },
              backgroundColor: Colors.white.withAlpha(200),
              selectedColor: Colors.deepOrange,
              checkmarkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide.none,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DisasterStyle {
  final IconData icon;
  final Color color;
  const _DisasterStyle(this.icon, this.color);
}
