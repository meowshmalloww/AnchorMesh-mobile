import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/connectivity_service.dart' hide AlertLevel;
import '../services/disaster_service.dart';
import '../theme/resq_theme.dart';
import '../painters/custom_borders.dart';
import 'disaster_map_page.dart';

/// ResQ Home Page - Premium Redesign
///
/// A mission-critical home screen with custom design language,
/// physics-based animations, and mesh network visualization.
class HomePage extends StatefulWidget {
  final Function(int)? onTabChange;

  const HomePage({super.key, this.onTabChange});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final BLEService _bleService = BLEService.instance;
  final DisasterService _disasterService = DisasterService.instance;
  final ConnectivityChecker _connectivityChecker = ConnectivityChecker.instance;

  AlertLevel _alertLevel = AlertLevel.peace;
  BLEConnectionState _bleState = BLEConnectionState.idle;
  bool _isOnline = true;
  int _activeSosCount = 0;

  StreamSubscription? _alertSub;
  StreamSubscription? _bleSub;
  StreamSubscription? _connectSub;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _loadData();
  }

  void _setupListeners() {
    _alertSub = _disasterService.levelStream.listen((level) {
      if (mounted) setState(() => _alertLevel = level);
    });

    _bleSub = _bleService.connectionState.listen((state) {
      if (mounted) setState(() => _bleState = state);
    });

    _connectSub = _connectivityChecker.statusStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  Future<void> _loadData() async {
    final packets = await _bleService.getActivePackets();
    if (mounted) {
      setState(() => _activeSosCount = packets.length);
    }
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _bleSub?.cancel();
    _connectSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.resq;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            _buildTopBar(colors),

            // Alert banner
            if (_alertLevel != AlertLevel.peace)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: _buildAlertBanner(colors),
              ),

            // Status pills
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildStatusRow(colors),
            ),

            const SizedBox(height: 16),

            const Spacer(),

            // Placeholder or Info Text instead of SOS Button
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 64,
                    color: colors.textSecondary.withAlpha(50),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SYSTEM READY',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Bottom action card
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: _buildDisasterCard(colors),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(ResQColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          // Logo / Title
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ResQ',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              Text(
                'MESH NETWORK',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Connection indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: ShapeDecoration(
              color: _isOnline
                  ? colors.statusOnline.withAlpha(38)
                  : colors.statusOffline.withAlpha(38),
              shape: const PillChamferBorder(chamferSize: 4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isOnline
                        ? colors.statusOnline
                        : colors.statusOffline,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isOnline ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    color: _isOnline
                        ? colors.statusOnline
                        : colors.statusOffline,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(ResQColors colors) {
    return Row(
      children: [
        Expanded(
          child: _buildStatusPill(
            icon: Icons.bluetooth,
            label: 'Mesh',
            value: _getBleStatusText(),
            color: _getBleStatusColor(colors),
            colors: colors,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatusPill(
            icon: Icons.sensors,
            label: 'Active',
            value: '$_activeSosCount SOS',
            color: _activeSosCount > 0 ? colors.accent : colors.textSecondary,
            colors: colors,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ResQColors colors,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: colors.surfaceElevated,
        shape: TacticalCardBorder(
          topLeftBevel: 12,
          bottomRightBevel: 12,
          radius: 8,
          side: BorderSide(color: colors.meshLine, width: 1),
        ),
        shadows: [
          BoxShadow(
            color: colors.shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withAlpha(38),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertBanner(ResQColors colors) {
    final color = _alertLevel == AlertLevel.disaster
        ? colors.accent
        : colors.statusWarning;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: color.withAlpha(38),
        shape: HexagonalBevelBorder(
          bevelDepth: 0.08,
          side: BorderSide(color: color, width: 1.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _alertLevel.label.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  _alertLevel.description,
                  style: TextStyle(color: color.withAlpha(204), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisasterCard(ResQColors colors) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DisasterMapPage()),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: ShapeDecoration(
          color: colors.surfaceElevated,
          shape: TacticalCardBorder(
            topLeftBevel: 20,
            bottomRightBevel: 20,
            radius: 12,
            side: BorderSide(color: colors.meshLine, width: 1),
          ),
          shadows: [
            BoxShadow(
              color: colors.shadowColor,
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.accent, colors.accent.withAlpha(179)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.public, color: colors.textOnAccent, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DISASTER MAP',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'View global events & local hazards',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.textSecondary, size: 24),
          ],
        ),
      ),
    );
  }

  String _getBleStatusText() {
    switch (_bleState) {
      case BLEConnectionState.meshActive:
        return 'Active';
      case BLEConnectionState.broadcasting:
        return 'Sending';
      case BLEConnectionState.scanning:
        return 'Scanning';
      case BLEConnectionState.bluetoothOff:
        return 'BT Off';
      case BLEConnectionState.unavailable:
        return 'N/A';
      case BLEConnectionState.idle:
        return 'Idle';
    }
  }

  Color _getBleStatusColor(ResQColors colors) {
    switch (_bleState) {
      case BLEConnectionState.meshActive:
        return colors.statusOnline;
      case BLEConnectionState.broadcasting:
      case BLEConnectionState.scanning:
        return colors.accentSecondary;
      case BLEConnectionState.bluetoothOff:
      case BLEConnectionState.unavailable:
        return colors.statusOffline;
      case BLEConnectionState.idle:
        return colors.textSecondary;
    }
  }
}
