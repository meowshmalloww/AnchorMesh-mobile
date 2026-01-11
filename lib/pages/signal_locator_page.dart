import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:compassx/compassx.dart';
import 'package:geolocator/geolocator.dart';
import '../services/ble_service.dart';
import '../utils/rssi_calculator.dart';
import '../models/sos_packet.dart';
import '../models/sos_status.dart';
import '../painters/compass_painter.dart';

/// Signal Locator page for finding SOS signals
/// Uses Kalman filter for RSSI smoothing and compass fusion for direction
class SignalLocatorPage extends StatefulWidget {
  const SignalLocatorPage({super.key});

  @override
  State<SignalLocatorPage> createState() => _SignalLocatorPageState();
}

class _SignalLocatorPageState extends State<SignalLocatorPage>
    with TickerProviderStateMixin {
  final BLEService _bleService = BLEService.instance;
  final RSSICalculator _rssiCalculator = RSSICalculator();
  final DirectionFinder _directionFinder = DirectionFinder();
  final Map<String, KalmanFilter> _kalmanFilters = {};

  // State
  final ValueNotifier<double?> _headingNotifier = ValueNotifier<double?>(null);
  // Keep _heading for logic reference where needed without UI updates
  double? get _heading => _headingNotifier.value;

  bool _isScanning = false;
  bool _isCalibrating = false;
  String? _selectedDeviceId;
  double _currentRSSI = -100;
  double _smoothedRSSI = -100;
  double _estimatedDistance = 0;
  int? _bestHeading;

  // Animation
  late AnimationController _pulseController;
  late AnimationController _radarController;

  // Subscriptions
  StreamSubscription<CompassXEvent>? _compassSub;
  StreamSubscription<SOSPacket>? _packetSub;
  Timer? _scanTimer;

  // Nearby devices
  List<SOSPacket> _nearbyDevices = [];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _setupCompass();
    _loadNearbyDevices();
  }

  void _setupCompass() {
    _compassSub = CompassX.events.listen((event) {
      if (mounted) {
        // Optimization: Update notifier instead of setState
        _headingNotifier.value = event.heading;

        // If calibrating, record RSSI at this heading
        if (_isCalibrating && _selectedDeviceId != null) {
          _directionFinder.addReading(
            event.heading,
            _currentRSSI.round(),
          );
        }
      }
    });
  }

  Future<void> _loadNearbyDevices() async {
    final packets = await _bleService.getActivePackets();
    if (mounted) {
      setState(() => _nearbyDevices = packets);
    }
  }

  void _startScanning() {
    HapticFeedback.mediumImpact();
    setState(() => _isScanning = true);

    _packetSub = _bleService.onPacketReceived.listen((packet) {
      _handlePacketReceived(packet);
    });

    _bleService.startScanning();

    // Refresh device list periodically
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadNearbyDevices();
    });
  }

  void _stopScanning() {
    setState(() => _isScanning = false);
    _packetSub?.cancel();
    _scanTimer?.cancel();
    _bleService.stopScanning();
  }

  void _handlePacketReceived(SOSPacket packet) {
    final deviceId = packet.userId.toRadixString(16);
    final rssi = packet.rssi ?? -80;

    // Get or create Kalman filter for this device
    _kalmanFilters.putIfAbsent(
      deviceId,
      () => KalmanFilter(initialEstimate: rssi.toDouble()),
    );

    // Apply Kalman filter
    final smoothed = _kalmanFilters[deviceId]!.filter(rssi.toDouble());

    // Also add to EMA calculator
    _rssiCalculator.addSample(deviceId, rssi);

    if (deviceId == _selectedDeviceId) {
      setState(() {
        _currentRSSI = rssi.toDouble();
        _smoothedRSSI = smoothed;
        _estimatedDistance = RSSICalculator.calculateDistance(smoothed.round());
      });

      // Add reading for direction finding if calibrating
      if (_isCalibrating && _heading != null) {
        _directionFinder.addReading(_heading!, smoothed.round());

        // Check if we have enough data
        if (_directionFinder.hasEnoughData()) {
          setState(() {
            _bestHeading = _directionFinder.getStrongestHeading();
          });
        }
      }
    }

    // Update nearby devices
    final idx = _nearbyDevices.indexWhere((p) => p.userId == packet.userId);
    if (idx >= 0) {
      setState(() => _nearbyDevices[idx] = packet);
    } else {
      setState(() => _nearbyDevices.add(packet));
    }
  }

  void _selectDevice(SOSPacket packet) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDeviceId = packet.userId.toRadixString(16);
      _currentRSSI = packet.rssi?.toDouble() ?? -80;
      _smoothedRSSI = _currentRSSI;
      _estimatedDistance = RSSICalculator.calculateDistance(
        _currentRSSI.round(),
      );
    });

    // Reset direction finder for new target
    _directionFinder.clear();
    _bestHeading = null;
  }

  void _startCalibration() {
    HapticFeedback.mediumImpact();
    setState(() => _isCalibrating = true);
    _directionFinder.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Slowly rotate 360° while holding phone flat'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
      ),
    );
  }

  void _stopCalibration() {
    setState(() {
      _isCalibrating = false;
      _bestHeading = _directionFinder.getStrongestHeading();
    });

    if (_bestHeading != null) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Signal strongest at $_bestHeading°'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _packetSub?.cancel();
    _scanTimer?.cancel();
    _pulseController.dispose();
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Scan button row
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isScanning ? _stopScanning : _startScanning,
                        icon: Icon(_isScanning ? Icons.stop : Icons.radar),
                        label: Text(
                          _isScanning ? 'Stop Scanning' : 'Start Scanning',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isScanning
                              ? Colors.red
                              : Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Selected device info
              if (_selectedDeviceId != null) ...[
                _buildProximityIndicator(isDark),
                const SizedBox(height: 20),
                _buildSignalStats(isDark),
                const SizedBox(height: 20),
                _buildSignalStats(isDark),
                const SizedBox(height: 20),
                _buildDirectionFinder(isDark),
                const SizedBox(height: 20),
                _buildDeviceActions(isDark),
              ] else ...[
                _buildNoSelectionCard(isDark),
              ],

              const SizedBox(height: 20),

              // Nearby devices list
              _buildNearbyDevicesList(isDark),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoSelectionCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.radar, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _isScanning ? 'Scanning for signals...' : 'Start scanning',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a device below to locate',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          if (!_isScanning) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _startScanning,
              icon: const Icon(Icons.search),
              label: const Text('Start Scanning'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProximityIndicator(bool isDark) {
    // Calculate color based on RSSI (hot = close, cold = far)
    final normalizedRSSI = ((_smoothedRSSI + 100) / 60).clamp(0.0, 1.0);
    final color = Color.lerp(Colors.blue, Colors.red, normalizedRSSI)!;
    final proximityText = _getProximityText();

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse =
            math.sin(_pulseController.value * 2 * math.pi) * 0.3 + 1.0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                color.withAlpha(50),
                color.withAlpha(20),
                Colors.transparent,
              ],
              radius: 0.8 * pulse,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(100), width: 2),
          ),
          child: Column(
            children: [
              // Hot/Cold indicator
              Text(
                proximityText,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),

              // Distance estimate
              Text(
                _estimatedDistance < 100
                    ? '~${_estimatedDistance.toStringAsFixed(1)}m'
                    : '~${(_estimatedDistance / 1000).toStringAsFixed(2)}km',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),

              const SizedBox(height: 20),

              // Visual temperature bar
              Container(
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [
                      Colors.blue,
                      Colors.cyan,
                      Colors.yellow,
                      Colors.orange,
                      Colors.red,
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left:
                          (normalizedRSSI *
                              MediaQuery.of(context).size.width *
                              0.7) -
                          10,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: color.withAlpha(150),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('❄️ COLD', style: TextStyle(fontSize: 10)),
                  Text('🔥 HOT', style: TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _getProximityText() {
    if (_smoothedRSSI > -50) return '🔥 VERY HOT';
    if (_smoothedRSSI > -60) return '🔥 HOT';
    if (_smoothedRSSI > -70) return '🌡️ WARM';
    if (_smoothedRSSI > -80) return '❄️ COOL';
    if (_smoothedRSSI > -90) return '❄️ COLD';
    return '🥶 VERY COLD';
  }

  Widget _buildSignalStats(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Signal Analysis',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'Raw RSSI',
                '${_currentRSSI.round()} dBm',
                Colors.orange,
              ),
              _buildStatItem(
                'Kalman',
                '${_smoothedRSSI.round()} dBm',
                Colors.green,
              ),
              _buildStatItem(
                'Quality',
                RSSICalculator.getSignalStrength(_smoothedRSSI.round()),
                Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDirectionFinder(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.explore, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Direction Finder',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: _isCalibrating
                    ? _stopCalibration
                    : _startCalibration,
                child: Text(_isCalibrating ? 'Stop' : 'Calibrate'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Compass with direction indicator
          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Compass ring
                ValueListenableBuilder<double?>(
                  valueListenable: _headingNotifier,
                  builder: (context, heading, child) {
                    return AnimatedBuilder(
                      animation: _radarController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: -((heading ?? 0) * math.pi / 180),
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.grey[400]!,
                                width: 2,
                              ),
                            ),
                            child: CustomPaint(
                              painter: CompassPainter(
                                heading: heading ?? 0,
                                bestHeading: _bestHeading,
                                isCalibrating: _isCalibrating,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

                // Center icon
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _isCalibrating ? Colors.orange : Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isCalibrating ? Icons.sync : Icons.my_location,
                    color: Colors.white,
                    size: 30,
                  ),
                ),

                // North indicator
                const Positioned(
                  top: 5,
                  child: Text(
                    'N',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_bestHeading != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_upward, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Signal strongest at $_bestHeading°',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_isCalibrating) ...[
            const SizedBox(height: 12),
            const Text(
              'Rotate slowly for best results',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceActions(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.touch_app, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Actions',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sendDirectPing,
              icon: const Icon(Icons.notifications_active),
              label: const Text('Send Direct Ping (Test)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendDirectPing() async {
    if (_selectedDeviceId == null) return;

    // Find selected packet
    final packet = _nearbyDevices.firstWhere(
      (p) => p.userId.toRadixString(16) == _selectedDeviceId,
      orElse: () => _nearbyDevices.first, // Fallback (shouldn't happen)
    );

    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sending Direct Ping...')));

    // Get location for packet
    double lat = 0;
    double lon = 0;
    try {
      final pos = await Geolocator.getCurrentPosition();
      lat = pos.latitude;
      lon = pos.longitude;
    } catch (_) {}

    final success = await _bleService.sendTargetMessage(
      targetUserId: packet.userId,
      latitude: lat,
      longitude: lon,
      status: SOSStatus.safe, // Using SAFE as 'Ping/Ack' for now
    );

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ping Sent!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send ping'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildNearbyDevicesList(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.devices, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Nearby Signals',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${_nearbyDevices.length} found',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_nearbyDevices.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _isScanning ? 'Searching...' : 'No signals detected',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ),
            )
          else
            ...List.generate(_nearbyDevices.length.clamp(0, 5), (index) {
              final packet = _nearbyDevices[index];
              final deviceId = packet.userId.toRadixString(16).toUpperCase();
              final isSelected =
                  _selectedDeviceId == packet.userId.toRadixString(16);
              final rssi = packet.rssi ?? -80;
              final color = Color(packet.status.colorValue);

              return InkWell(
                onTap: () => _selectDevice(packet),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withAlpha(30)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected ? Border.all(color: color) : null,
                  ),
                  child: Row(
                    children: [
                      Icon(packet.status.icon, color: color, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              deviceId,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            Text(
                              packet.status.description,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              '${packet.latitude.toStringAsFixed(5)}, ${packet.longitude.toStringAsFixed(5)}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$rssi dBm',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: rssi > -70
                                  ? Colors.green
                                  : rssi > -85
                                  ? Colors.orange
                                  : Colors.red,
                            ),
                          ),
                          Text(
                            RSSICalculator.getSignalStrength(rssi),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
