import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import '../models/sos_packet.dart';
import '../models/sos_status.dart';
import '../services/ble_service.dart';
import '../services/connectivity_service.dart';
import '../utils/rssi_calculator.dart';
import '../widgets/adaptive/adaptive_widgets.dart';

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

  // Mesh feedback
  int _handshakeCount = 0;
  int _echoCount = 0;
  int _echoSources = 0;
  VerificationStatus? _myVerification;
  bool _isWifiEnabled = false;
  Timer? _wifiCheckTimer;

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
  StreamSubscription? _echoSubscription;
  StreamSubscription? _handshakeSubscription;
  StreamSubscription? _verificationSubscription;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
    _setupListeners();
    _loadActivePackets();

    // Initial WiFi check
    _checkWifiStatus();

    // Check WiFi status occasionally while open
    _wifiCheckTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkWifiStatus(),
    );
  }

  Future<void> _checkWifiStatus() async {
    final result = await _bleService.checkWifiStatus();
    if (mounted && result != _isWifiEnabled) {
      setState(() => _isWifiEnabled = result);
    }
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
        showWarningSnackBar(context, error);
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

    // Echo detection - when our packet is relayed back
    _echoSubscription = _bleService.onEchoDetected.listen((event) {
      if (mounted) {
        setState(() {
          _echoCount = _bleService.echoCount;
          _echoSources = _bleService.echoSources;
        });
        // Show feedback
        showSuccessSnackBar(context, 'Signal relayed! $_echoCount copies out there');
      }
    });

    // Handshake count updates
    _handshakeSubscription = _bleService.onHandshakeUpdate.listen((count) {
      if (mounted) {
        setState(() => _handshakeCount = count);
      }
    });

    // Verification updates
    _verificationSubscription = _bleService.onVerificationUpdate.listen((
      status,
    ) {
      if (mounted) {
        // Check if this is verification for our broadcast
        _bleService.getUserId().then((userId) {
          if (status.userId == userId) {
            setState(() => _myVerification = status);
          }
        });
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
        ? ' - ${RSSICalculator.getProximityDescription(distance)}'
        : '';

    showAdaptiveSnackBar(
      context: context,
      message: '${packet.status.label} received$distanceText',
      icon: packet.status.icon,
      backgroundColor: Color(packet.status.colorValue),
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
    _echoSubscription?.cancel();
    _handshakeSubscription?.cancel();
    _verificationSubscription?.cancel();
    _wifiCheckTimer?.cancel();
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
    // Haptic feedback
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 100);
    }
    HapticFeedback.heavyImpact();

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
        showWarningSnackBar(context, 'Location required');
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
              AdaptiveInfoCard(
                icon: Icons.battery_alert,
                color: Colors.orange,
                title: 'Low Power Mode ON',
                subtitle: 'Disable for reliable mesh.',
                isBordered: true,
                margin: const EdgeInsets.only(bottom: 16),
              ),

            // WiFi Warning
            if (_isWifiEnabled)
              AdaptiveInfoCard(
                icon: Icons.wifi_off,
                color: Colors.blue,
                title: 'Starlink/WiFi is ON',
                subtitle: 'Turn off for better mesh range if not needed.',
                isBordered: true,
                margin: const EdgeInsets.only(bottom: 16),
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
                            _isBroadcasting ? Icons.stop : _selectedStatus.icon,
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

            // Mesh feedback stats (only when broadcasting)
            if (_isBroadcasting) ...[
              _buildMeshFeedbackCard(),
              const SizedBox(height: 20),
            ],

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
            AdaptiveInfoCard(
              icon: Icons.info_outline,
              color: Colors.blue,
              title: 'Mesh SOS',
              subtitle: 'No internet? Your signal relays via nearby phones. Keep app open for best results.',
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
    final verification = _bleService.getVerificationStatus(packet.userId);

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
            child: Icon(packet.status.icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      packet.status.description,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    if (verification != null && verification.isVerified) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '✓ VERIFIED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  "${packet.latitude.toStringAsFixed(4)}, ${packet.longitude.toStringAsFixed(4)} • ${ageMinutes}m ago",
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                if (verification != null)
                  Text(
                    'Confirmed by ${verification.confirmations} device${verification.confirmations != 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
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

  Widget _buildMeshFeedbackCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _echoCount > 0
              ? Colors.green.withAlpha(100)
              : Colors.grey.withAlpha(50),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.share,
                size: 18,
                color: _echoCount > 0 ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              const Text(
                'Mesh Status',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatColumn(
                icon: Icons.repeat,
                value: '$_echoCount',
                label: 'Echoes',
                color: Colors.green,
              ),
              _buildStatColumn(
                icon: Icons.devices,
                value: '$_echoSources',
                label: 'Relays',
                color: Colors.blue,
              ),
              _buildStatColumn(
                icon: Icons.handshake,
                value: '$_handshakeCount',
                label: 'Handshakes',
                color: Colors.purple,
              ),
              _buildStatColumn(
                icon: Icons.check_circle,
                value: _myVerification?.isVerified == true ? 'YES' : 'NO',
                label: 'Verified',
                color: _myVerification?.isVerified == true
                    ? Colors.green
                    : Colors.orange,
              ),
            ],
          ),
          if (_echoCount > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '$_echoCount copies being carried by $_echoSources devices',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatColumn({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }
}
