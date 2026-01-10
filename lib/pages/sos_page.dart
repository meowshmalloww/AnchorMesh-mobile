import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import '../models/sos_packet.dart';
import '../models/sos_status.dart';
import '../services/ble_service.dart';
import '../services/connectivity_service.dart';
import '../theme/resq_theme.dart';
import '../utils/rssi_calculator.dart';
// import '../services/connectivity_service.dart'; // Already imported above if needed, check lines 1-10

class SOSPage extends StatefulWidget {
  const SOSPage({super.key});

  @override
  State<SOSPage> createState() => _SOSPageState();
}

class _SOSPageState extends State<SOSPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Location
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
  StreamSubscription<Position>? _locationSub; // New location subscription

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAnimation();
    _setupListeners();
    _loadActivePackets();

    // Initial WiFi check
    _checkWifiStatus();
    _getCurrentLocation(); // Auto-fetch location on load
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkWifiStatus();
      _bleService.reinitializeEventChannel();
    }
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

    // Echo detection - when our packet is relayed back
    _echoSubscription = _bleService.onEchoDetected.listen((event) {
      if (mounted) {
        setState(() {
          _echoCount = _bleService.echoCount;
          _echoSources = _bleService.echoSources;
        });
        // Show feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📡 Signal relayed! $_echoCount copies out there'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
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
    _echoSubscription?.cancel();
    _handshakeSubscription?.cancel();
    _verificationSubscription?.cancel();
    _locationSub?.cancel();
    // _wifiCheckTimer?.cancel(); // Removed
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startLocationTracking() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Throttle updates: only if moved 10m
    );

    _locationSub?.cancel();
    _locationSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((position) {
          if (mounted) {
            setState(() {
              _latitude = position.latitude;
              _longitude = position.longitude;
            });

            // Update broadcast packet if active
            if (_isBroadcasting) {
              _bleService.startMeshMode(
                latitude: position.latitude,
                longitude: position.longitude,
                status: _selectedStatus,
              );
            }
          }
        });
  }

  Future<void> _getCurrentLocation() async {
    // Only used for initial fix
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
      }
    } catch (e) {
      if (mounted) {
        debugPrint("Location error: $e");
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
      _locationSub?.cancel(); // Stop tracking location
      setState(() => _isBroadcasting = false);
    } else {
      // Start location tracking first
      _startLocationTracking();

      if (_latitude == null || _longitude == null) {
        // Wait briefly for location
        await Future.delayed(const Duration(seconds: 1));
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
    final colors = context.resq;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top;
    const topBarHeight = 70.0;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Stack(
        children: [
          // Scrollable content
          SingleChildScrollView(
            padding: EdgeInsets.only(
              top: topPadding + topBarHeight + 8,
              left: 20,
              right: 20,
              bottom: 120,
            ),
            child: Column(
              children: [
                // Alert Banner
                if (_alertLevel != AlertLevel.peace)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildAlertBanner(colors),
                  ),

                // Low Power Warning
                if (_isLowPowerMode)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _buildWarningBanner(
                      icon: Icons.battery_alert,
                      text: "Low Power Mode ON. Mesh reliability reduced.",
                      color: Colors.orange,
                    ),
                  ),

                // WiFi Warning
                if (_isWifiEnabled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _buildWarningBanner(
                      icon: Icons.wifi_off,
                      text: "WiFi ON. Turn off for better range.",
                      color: Colors.blue,
                    ),
                  ),

                // Status Selector
                _buildStatusSelector(colors, isDark),

                const SizedBox(height: 20),

                // Giant SOS Button
                _buildMainSOSButton(colors),

                const SizedBox(height: 40),

                // Stats / Feedback
                if (_isBroadcasting)
                  _buildMeshStats(colors)
                else if (_receivedPackets.isNotEmpty)
                  _buildNearbySignals(colors),

                const SizedBox(height: 20),
              ],
            ),
          ),

          // Frosted top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: EdgeInsets.only(
                    top: topPadding + 16,
                    left: 20,
                    right: 20,
                    bottom: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceElevated.withAlpha(isDark ? 115 : 140),
                    border: Border(
                      bottom: BorderSide(
                        color: colors.meshLine.withAlpha(76),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: _buildTopBarContent(colors),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBarContent(ResQColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.shield_outlined, color: colors.accent, size: 24),
            const SizedBox(width: 12),
            Text(
              'EMERGENCY',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
          ],
        ),

        // Connection Status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: ShapeDecoration(
            color: _bleState == BLEConnectionState.meshActive
                ? colors.statusOnline.withAlpha(30)
                : colors.surfaceElevated.withAlpha(128),
            shape: const StadiumBorder(),
            shadows: [
              if (_bleState == BLEConnectionState.meshActive)
                BoxShadow(
                  color: colors.statusOnline.withAlpha(50),
                  blurRadius: 10,
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _bleState == BLEConnectionState.meshActive
                      ? colors.statusOnline
                      : colors.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _bleState == BLEConnectionState.meshActive
                    ? 'MESH ACTIVE'
                    : 'STANDBY',
                style: TextStyle(
                  color: _bleState == BLEConnectionState.meshActive
                      ? colors.statusOnline
                      : colors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSelector(ResQColors colors, bool isDark) {
    return Column(
      children: [
        Text(
          'SELECT SITUATION',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.meshLine.withAlpha(20)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: SOSStatus.values.where((s) => s != SOSStatus.safe).map((
              status,
            ) {
              final isSelected = _selectedStatus == status;
              final statusColor = Color(status.colorValue);

              return Expanded(
                child: GestureDetector(
                  onTap: _isBroadcasting
                      ? null
                      : () => setState(() => _selectedStatus = status),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? statusColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          status.icon,
                          size: 20,
                          color: isSelected
                              ? Colors.white
                              : colors.textSecondary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status.label, // "EMERGENCY" etc
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : colors.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMainSOSButton(ResQColors colors) {
    // Determine color based on status (or default red)
    final statusColor = Color(_selectedStatus.colorValue);

    return Center(
      child: GestureDetector(
        onTapDown: (_) => Vibration.vibrate(duration: 20),
        onTap: _toggleBroadcast,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isBroadcasting
                  ? [statusColor, statusColor.withAlpha(200)]
                  : [colors.surfaceElevated, colors.surface],
            ),
            border: Border.all(
              color: _isBroadcasting
                  ? statusColor
                  : colors.meshLine.withAlpha(50),
              width: 1,
            ),
            boxShadow: [
              // Outer glow when active
              if (_isBroadcasting)
                BoxShadow(
                  color: statusColor.withAlpha(100),
                  blurRadius: 50,
                  spreadRadius: 10,
                ),
              // Inner depth
              BoxShadow(
                color: colors.shadowColor,
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ripples
              if (_isBroadcasting)
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: statusColor.withAlpha(100),
                        width: 2,
                      ),
                    ),
                  ),
                ),

              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isBroadcasting ? Icons.stop_rounded : _selectedStatus.icon,
                    size: 64,
                    color: _isBroadcasting ? Colors.white : statusColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isBroadcasting ? "STOP" : "ACTIVATE",
                    style: TextStyle(
                      color: _isBroadcasting
                          ? Colors.white
                          : colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  if (_isBroadcasting)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        "BROADCASTING",
                        style: TextStyle(
                          color: Colors.white.withAlpha(200),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMeshStats(ResQColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceElevated.withAlpha(200),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.meshLine.withAlpha(50)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hub, color: colors.accent, size: 16),
              const SizedBox(width: 8),
              Text(
                "MESH NETWORK FEEDBACK",
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem("RELAYS", "$_echoSources", colors),
              _buildStatItem("ECHOES", "$_echoCount", colors),
              _buildStatItem("HANDSHAKES", "$_handshakeCount", colors),
            ],
          ),
          const SizedBox(height: 12),
          _buildStatItem(
            "VERIFIED",
            _myVerification?.isVerified == true ? "YES" : "NO",
            colors,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, ResQColors colors) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildNearbySignals(ResQColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            "NEARBY SIGNALS (${_receivedPackets.length})",
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
        ..._receivedPackets
            .take(3)
            .map((packet) => _buildPacketCard(packet, colors)),
      ],
    );
  }

  Widget _buildPacketCard(SOSPacket packet, ResQColors colors) {
    final statusColor = Color(packet.status.colorValue);
    final distance = _bleService.rssiCalculator.getSmoothedDistance(
      packet.userId.toRadixString(16),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withAlpha(50)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(packet.status.icon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  packet.status.description,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "${(packet.ageSeconds / 60).toStringAsFixed(0)}m ago • ${distance != null ? "${distance.round()}m away" : "Unknown dist"}",
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertBanner(ResQColors colors) {
    final isDisaster = _alertLevel == AlertLevel.disaster;
    final color = isDisaster ? Colors.red : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isDisaster
                  ? "DISASTER ALERT ACTIVE"
                  : "ALERT: ${_alertLevel.name.toUpperCase()}",
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
