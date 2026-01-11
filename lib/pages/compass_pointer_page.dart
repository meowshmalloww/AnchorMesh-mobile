import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import '../services/ble_service.dart';
import '../models/sos_packet.dart';
import '../widgets/offline/compass_pointer.dart';

class CompassPointerPage extends StatefulWidget {
  const CompassPointerPage({super.key});

  @override
  State<CompassPointerPage> createState() => _CompassPointerPageState();
}

class _CompassPointerPageState extends State<CompassPointerPage> {
  final BLEService _bleService = BLEService.instance;

  // Sensors
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<SOSPacket>? _scanSub;

  double _heading = 0;
  Position? _currentPosition;

  // Target
  SOSPacket? _targetPacket;
  double _targetBearing = 0;
  double _targetDistance = 0;

  // Nearby for selection
  List<SOSPacket> _nearbySignals = [];

  @override
  void initState() {
    super.initState();
    _initSensors();
    _startScanning();
  }

  void _initSensors() {
    _compassSub = FlutterCompass.events?.listen((event) {
      if (mounted) setState(() => _heading = event.heading ?? 0);
    });

    final settings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    );
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((
      pos,
    ) {
      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _updateNavigationVector();
        });
      }
    });
  }

  void _startScanning() {
    // Initial load
    _bleService.getActivePackets().then((packets) {
      if (mounted) setState(() => _nearbySignals = packets);
    });

    // Listen for updates
    _scanSub = _bleService.onPacketReceived.listen((packet) {
      final index = _nearbySignals.indexWhere((p) => p.userId == packet.userId);
      if (index >= 0) {
        _nearbySignals[index] = packet;
      } else {
        _nearbySignals.add(packet);
      }

      // Update target if it's the one we are tracking
      if (_targetPacket?.userId == packet.userId) {
        _targetPacket = packet;
        _updateNavigationVector();
      }

      if (mounted) setState(() {});
    });

    _bleService.startScanning();
  }

  void _updateNavigationVector() {
    if (_currentPosition == null || _targetPacket == null) return;

    final dist = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _targetPacket!.latitude,
      _targetPacket!.longitude,
    );

    final bearing = Geolocator.bearingBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _targetPacket!.latitude,
      _targetPacket!.longitude,
    );

    setState(() {
      _targetDistance = dist;
      _targetBearing = bearing;
    });
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _posSub?.cancel();
    _scanSub?.cancel();
    _bleService.stopScanning();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_targetPacket == null) {
      return _buildTargetSelector();
    }

    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: CompassPointer(
              heading: _heading,
              bearing: _targetBearing,
              distance: _targetDistance,
              targetName: _targetPacket?.status.label ?? "Unknown",
              isAccuracyLow:
                  _currentPosition?.accuracy != null &&
                  _currentPosition!.accuracy > 20,
            ),
          ),

          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _targetPacket = null),
              icon: const Icon(Icons.stop),
              label: const Text("STOP NAVIGATION"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetSelector() {
    return Column(
      children: [
        const SizedBox(height: 20),
        const Text(
          "SELECT TARGET",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        if (_nearbySignals.isEmpty)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Scanning for signals..."),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _nearbySignals.length,
              itemBuilder: (context, index) {
                final packet = _nearbySignals[index];
                final color = Color(packet.status.colorValue);

                // Calculate distance estimate if we have location
                String distText = "";
                if (_currentPosition != null) {
                  final d = Geolocator.distanceBetween(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                    packet.latitude,
                    packet.longitude,
                  );
                  distText = d < 1000
                      ? "${d.round()}m"
                      : "${(d / 1000).toStringAsFixed(1)}km";
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: color, width: 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withAlpha(50),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(packet.status.icon, color: color),
                    ),
                    title: Text(
                      packet.status.label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      "${packet.userId.toRadixString(16).toUpperCase()} • $distText",
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      setState(() {
                        _targetPacket = packet;
                        _updateNavigationVector();
                      });
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
