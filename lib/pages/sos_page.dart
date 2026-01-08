import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/sos_packet.dart';
import '../models/sos_status.dart';
import '../services/ble_service.dart';
import '../services/connectivity_service.dart';
import '../utils/rssi_calculator.dart';

class SOSPage extends StatefulWidget {
  const SOSPage({super.key});

  @override
  State<SOSPage> createState() => _SOSPageState();
}

class _SOSPageState extends State<SOSPage> with TickerProviderStateMixin {
  // Location
  String _locationMessage = "Tap to get location";
  bool _isLoadingLocation = false;
  double? _latitude;
  double? _longitude;

  // BLE State
  SOSStatus _selectedStatus = SOSStatus.sos;
  bool _isBroadcasting = false;
  BLEConnectionState _bleState = BLEConnectionState.idle;
  AlertLevel _alertLevel = AlertLevel.peace;
  final bool _isLowPowerMode = false;

  // Received packets
  final List<SOSPacket> _receivedPackets = [];

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Services
  final BLEService _bleService = BLEService.instance;
  final DisasterMonitor _disasterMonitor = DisasterMonitor.instance;

  // Subscriptions
  StreamSubscription? _stateSubscription;
  StreamSubscription? _packetSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _alertSubscription;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
    _setupListeners();
    _loadActivePackets();
  }

  void _setupAnimation() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _setupListeners() {
    _stateSubscription = _bleService.connectionState.listen((state) {
      if (mounted) setState(() => _bleState = state);
    });

    _packetSubscription = _bleService.onPacketReceived.listen((packet) {
      if (mounted) {
        setState(() {
          // Update or add packet
          final idx = _receivedPackets.indexWhere(
            (p) => p.userId == packet.userId,
          );
          if (idx >= 0) {
            _receivedPackets[idx] = packet;
          } else {
            _receivedPackets.insert(0, packet);
          }
        });
        _showPacketNotification(packet);
      }
    });

    _errorSubscription = _bleService.onError.listen((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.orange),
        );
      }
    });

    _alertSubscription = _disasterMonitor.levelStream.listen((level) {
      if (mounted) {
        setState(() => _alertLevel = level);
        if (level == AlertLevel.disaster) {
          _autoActivateMesh();
        }
      }
    });
  }

  Future<void> _loadActivePackets() async {
    final packets = await _bleService.getActivePackets();
    if (mounted) {
      setState(() => _receivedPackets.addAll(packets));
    }
  }

  void _showPacketNotification(SOSPacket packet) {
    final distance = _bleService.rssiCalculator.getSmoothedDistance(
      packet.userId.toRadixString(16),
    );
    final distanceText = distance != null
        ? ' • ${RSSICalculator.getProximityDescription(distance)}'
        : '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${packet.status.label} received$distanceText'),
        backgroundColor: Color(packet.status.colorValue),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _autoActivateMesh() async {
    if (!_isBroadcasting && _latitude != null && _longitude != null) {
      await _toggleBroadcast();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stateSubscription?.cancel();
    _packetSubscription?.cancel();
    _errorSubscription?.cancel();
    _alertSubscription?.cancel();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationMessage = "Fetching...";
    });

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          setState(() {
            _locationMessage = "Location disabled";
            _isLoadingLocation = false;
          });
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _locationMessage = "Permission denied";
              _isLoadingLocation = false;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationMessage = "Permission blocked";
            _isLoadingLocation = false;
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _locationMessage =
              "${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}";
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationMessage = "Error";
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _toggleBroadcast() async {
    if (_isBroadcasting) {
      await _bleService.stopAll();
      _pulseController.stop();
      setState(() => _isBroadcasting = false);
    } else {
      if (_latitude == null || _longitude == null) {
        await _getCurrentLocation();
      }

      if (_latitude == null || _longitude == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Location required')));
        return;
      }

      final success = await _bleService.startMeshMode(
        latitude: _latitude!,
        longitude: _longitude!,
        status: _selectedStatus,
      );

      if (success) {
        _pulseController.repeat(reverse: true);
        setState(() => _isBroadcasting = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subColor = isDark ? Colors.white70 : Colors.black54;
    final statusColor = Color(_selectedStatus.colorValue);

    return Scaffold(
      appBar: AppBar(
        title: const Text("SOS Emergency"),
        actions: [
          // Alert level indicator
          if (_alertLevel != AlertLevel.peace)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _alertLevel == AlertLevel.disaster
                    ? Colors.red
                    : Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _alertLevel.label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          // BLE status
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              Icons.bluetooth,
              color: _bleState == BLEConnectionState.meshActive
                  ? Colors.blue
                  : Colors.grey,
              size: 20,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Low power warning
            if (_isLowPowerMode)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.battery_alert, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Low Power Mode ON. Disable for reliable mesh.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // Status selection
            const SizedBox(height: 8),
            Text(
              "SELECT YOUR STATUS",
              style: TextStyle(fontSize: 12, color: subColor, letterSpacing: 1),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: SOSStatus.values.where((s) => s != SOSStatus.safe).map((
                status,
              ) {
                final isSelected = _selectedStatus == status;
                final color = Color(status.colorValue);
                return GestureDetector(
                  onTap: _isBroadcasting
                      ? null
                      : () => setState(() => _selectedStatus = status),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? color : color.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          status.icon,
                          color: isSelected ? Colors.white : color,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          status.label,
                          style: TextStyle(
                            color: isSelected ? Colors.white : color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 30),

            // Main SOS button
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isBroadcasting ? _pulseAnimation.value : 1.0,
                  child: GestureDetector(
                    onTap: _toggleBroadcast,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        color: _isBroadcasting
                            ? statusColor
                            : statusColor.withAlpha(200),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withAlpha(
                              _isBroadcasting ? 150 : 80,
                            ),
                            blurRadius: _isBroadcasting ? 40 : 20,
                            spreadRadius: _isBroadcasting ? 12 : 4,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isBroadcasting
                                ? Icons.stop
                                : _selectedStatus.icon,
                            size: 36,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isBroadcasting ? "STOP" : _selectedStatus.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_isBroadcasting)
                            const Text(
                              "Broadcasting...",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 30),

            // Location
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.blue, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _locationMessage,
                      style: TextStyle(color: textColor, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    onPressed: _isLoadingLocation ? null : _getCurrentLocation,
                    icon: _isLoadingLocation
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),

            // Nearby SOS signals
            if (_receivedPackets.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.sensors, size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    "Nearby Signals (${_receivedPackets.length})",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ..._receivedPackets
                  .take(5)
                  .map((packet) => _buildPacketCard(packet)),
            ],

            // Help text
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.blue,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Mesh SOS",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "• No internet? Your signal relays via nearby phones\n• Keep app open for best results\n• Safe? Tap STOP to cancel",
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildPacketCard(SOSPacket packet) {
    final color = Color(packet.status.colorValue);
    final distance = _bleService.rssiCalculator.getSmoothedDistance(
      packet.userId.toRadixString(16),
    );
    final ageMinutes = packet.ageSeconds ~/ 60;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(
              packet.status.icon,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  packet.status.description,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  "${packet.latitude.toStringAsFixed(4)}, ${packet.longitude.toStringAsFixed(4)} • ${ageMinutes}m ago",
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (distance != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                distance < 100
                    ? "${distance.toStringAsFixed(0)}m"
                    : "${(distance / 1000).toStringAsFixed(1)}km",
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
