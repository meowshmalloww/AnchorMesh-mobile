import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ble_service.dart';
import '../services/connectivity_service.dart' hide AlertLevel;
import '../services/disaster_service.dart';
import '../theme/resq_theme.dart';
import '../painters/custom_borders.dart';
import '../widgets/sync_status_widget.dart';
import '../models/sos_packet.dart';
import '../home_screen.dart';
import 'disaster_map_page.dart';
import '../services/platform_service.dart';
import 'settings_page.dart';

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
  StreamSubscription? _packetSub; // New packet listener
  StreamSubscription? _connectSub;
  StreamSubscription? _powerModeSub;
  bool _isLowPowerMode = false;

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

    // START FIX: Listen for incoming SOS packets to update count
    _packetSub = _bleService.onPacketReceived.listen((_) {
      _loadData(); // Reload active packet count
    });
    // END FIX

    // Listen for Battery Saver Mode
    _powerModeSub = PlatformService.instance.lowPowerModeStream.listen((
      enabled,
    ) {
      if (mounted) setState(() => _isLowPowerMode = enabled);
      if (enabled) _showBatteryWarning();
    });

    // Initial check
    PlatformService.instance.checkLowPowerMode().then((enabled) {
      if (mounted && enabled) {
        setState(() => _isLowPowerMode = true);
        _showBatteryWarning();
      }
    });
  }

  void _showBatteryWarning() {
    // Check if banner already visible? Logic handled by build or simple banner
    // Banners are persistent until dismissed.
    // Using a persistent container in the build method is better than showMaterialBanner
    // because it handles state changes correctly.
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
    _packetSub?.cancel(); // Cancel packet listener
    _connectSub?.cancel();
    _powerModeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.resq;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top;
    const topBarHeight = 90.0;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Stack(
        children: [
          // Scrollable content
          SingleChildScrollView(
            padding: EdgeInsets.only(
              top:
                  topPadding +
                  topBarHeight +
                  30, // Added extra padding per user request
              bottom: 120,
            ),
            child: Column(
              children: [
                // Alert banner
                if (_alertLevel != AlertLevel.peace)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: _buildAlertBanner(colors),
                  ),

                // Battery Saver Warning
                if (_isLowPowerMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: _buildBatteryWarning(colors),
                  ),

                // Status pills
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildStatusRow(colors),
                ),

                const SizedBox(height: 80),

                // Placeholder or Info Text
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

                const SizedBox(height: 80),

                // Bottom action card
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: _buildDisasterCard(colors),
                ),
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
                    bottom: 20,
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
      children: [
        // Logo / Title
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AnchorMesh',
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
                  color: _isOnline ? colors.statusOnline : colors.statusOffline,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _isOnline ? 'ONLINE' : 'OFFLINE',
                style: TextStyle(
                  color: _isOnline ? colors.statusOnline : colors.statusOffline,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRow(ResQColors colors) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatusPill(
                icon: Icons.bluetooth,
                label: 'Mesh',
                value: _getBleStatusText(),
                color: _getBleStatusColor(colors),
                colors: colors,
                onTap: () => _showMeshStatusSheet(colors),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatusPill(
                icon: Icons.sensors,
                label: 'Active',
                value: '$_activeSosCount SOS',
                color: _activeSosCount > 0
                    ? colors.accent
                    : colors.textSecondary,
                colors: colors,
                onTap: () => _showActiveSOSSheet(colors),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Cloud Sync Status
        const SyncStatusWidget(compact: true, showSyncButton: false),
      ],
    );
  }

  Widget _buildStatusPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ResQColors colors,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap?.call();
      },
      child: Container(
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
            Icon(Icons.chevron_right, color: colors.textSecondary, size: 18),
          ],
        ),
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

  Widget _buildBatteryWarning(ResQColors colors) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: Colors.orange.withAlpha(40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.orange, width: 1.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.battery_alert, color: Colors.orange, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'SYSTEM BATTERY SAVER ON',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'System battery saver kills mesh capability. Please disable it.',
            style: TextStyle(color: colors.textPrimary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              // Navigate to Settings Page to enable OUR battery saver
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
            child: Row(
              children: [
                Text(
                  'Enable ResQ Battery Mode instead',
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                  ),
                ),
                const Icon(Icons.arrow_forward, size: 14, color: Colors.orange),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // MESH STATUS BOTTOM SHEET
  // ============================================================================

  void _showMeshStatusSheet(ResQColors colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _MeshStatusSheet(
        bleService: _bleService,
        bleState: _bleState,
        colors: colors,
      ),
    );
  }

  // ============================================================================
  // ACTIVE SOS BOTTOM SHEET
  // ============================================================================

  void _showActiveSOSSheet(ResQColors colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ActiveSOSSheet(
        bleService: _bleService,
        colors: colors,
        onNavigateToMap: (double lat, double lon) {
          Navigator.pop(context);
          // Navigate to map tab with coordinates
          homeScreenKey.currentState?.navigateToEmergency(lat, lon);
        },
      ),
    );
  }
}

// =============================================================================
// MESH STATUS SHEET WIDGET
// =============================================================================

class _MeshStatusSheet extends StatefulWidget {
  final BLEService bleService;
  final BLEConnectionState bleState;
  final ResQColors colors;

  const _MeshStatusSheet({
    required this.bleService,
    required this.bleState,
    required this.colors,
  });

  @override
  State<_MeshStatusSheet> createState() => _MeshStatusSheetState();
}

class _MeshStatusSheetState extends State<_MeshStatusSheet> {
  int _connectedDevices = 0;
  int _echoCount = 0;
  int _handshakeCount = 0;
  bool _isScanning = false;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    _loadMeshData();
    _stateSub = widget.bleService.connectionState.listen((_) {
      _loadMeshData();
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }

  void _loadMeshData() {
    if (mounted) {
      setState(() {
        _connectedDevices = widget.bleService.connectedDevices;
        _echoCount = widget.bleService.echoCount;
        _handshakeCount = widget.bleService.handshakeCount;
        _isScanning = widget.bleState == BLEConnectionState.scanning ||
            widget.bleState == BLEConnectionState.meshActive;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.meshLine, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.meshLine, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getStatusColor(colors).withAlpha(38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.bluetooth,
                    color: _getStatusColor(colors),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MESH NETWORK',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        _getStatusText(),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: colors.textSecondary),
                ),
              ],
            ),
          ),

          // Stats Grid
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.devices,
                        label: 'Connected',
                        value: '$_connectedDevices',
                        color: colors.statusOnline,
                        colors: colors,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.repeat,
                        label: 'Echoes',
                        value: '$_echoCount',
                        color: colors.accentSecondary,
                        colors: colors,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.handshake,
                        label: 'Handshakes',
                        value: '$_handshakeCount',
                        color: colors.accent,
                        colors: colors,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.radar,
                        label: 'Scanning',
                        value: _isScanning ? 'Active' : 'Idle',
                        color: _isScanning ? colors.statusOnline : colors.textSecondary,
                        colors: colors,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Info Text
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colors.textSecondary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'The mesh network allows devices to relay SOS signals even without internet connectivity.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom padding for safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ResQColors colors,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText() {
    switch (widget.bleState) {
      case BLEConnectionState.meshActive:
        return 'Active';
      case BLEConnectionState.broadcasting:
        return 'Broadcasting';
      case BLEConnectionState.scanning:
        return 'Scanning';
      case BLEConnectionState.bluetoothOff:
        return 'Bluetooth Off';
      case BLEConnectionState.unavailable:
        return 'Unavailable';
      case BLEConnectionState.idle:
        return 'Idle';
    }
  }

  Color _getStatusColor(ResQColors colors) {
    switch (widget.bleState) {
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

// =============================================================================
// ACTIVE SOS SHEET WIDGET
// =============================================================================

class _ActiveSOSSheet extends StatefulWidget {
  final BLEService bleService;
  final ResQColors colors;
  final Function(double lat, double lon) onNavigateToMap;

  const _ActiveSOSSheet({
    required this.bleService,
    required this.colors,
    required this.onNavigateToMap,
  });

  @override
  State<_ActiveSOSSheet> createState() => _ActiveSOSSheetState();
}

class _ActiveSOSSheetState extends State<_ActiveSOSSheet> {
  List<SOSPacket> _activePackets = [];
  bool _isLoading = true;
  StreamSubscription? _packetSub;

  @override
  void initState() {
    super.initState();
    _loadPackets();
    _packetSub = widget.bleService.onPacketReceived.listen((_) {
      _loadPackets();
    });
  }

  @override
  void dispose() {
    _packetSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPackets() async {
    final packets = await widget.bleService.getActivePackets();
    if (mounted) {
      setState(() {
        _activePackets = packets;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    return Container(
      margin: const EdgeInsets.all(16),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.meshLine, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.meshLine, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _activePackets.isNotEmpty
                        ? colors.accent.withAlpha(38)
                        : colors.textSecondary.withAlpha(38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.sensors,
                    color: _activePackets.isNotEmpty
                        ? colors.accent
                        : colors.textSecondary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ACTIVE SOS ALERTS',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        '${_activePackets.length} Signal${_activePackets.length != 1 ? 's' : ''}',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: colors.textSecondary),
                ),
              ],
            ),
          ),

          // Content
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            )
          else if (_activePackets.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: colors.statusOnline.withAlpha(100),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Active Emergencies',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All clear! No SOS signals detected nearby.',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: _activePackets.length,
                itemBuilder: (context, index) {
                  final packet = _activePackets[index];
                  return _buildSOSCard(packet, colors);
                },
              ),
            ),

          // Bottom padding for safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _buildSOSCard(SOSPacket packet, ResQColors colors) {
    final statusColor = Color(packet.status.colorValue);
    final packetTime = DateTime.fromMillisecondsSinceEpoch(packet.timestamp * 1000);
    final age = DateTime.now().difference(packetTime);
    final ageText = age.inMinutes < 1
        ? 'Just now'
        : age.inMinutes < 60
            ? '${age.inMinutes}m ago'
            : '${age.inHours}h ago';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withAlpha(100), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(38),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    packet.status.emoji,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      packet.status.label,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'ID: ${packet.userId.toRadixString(16).toUpperCase().padLeft(8, '0')}',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  ageText,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.location_on, color: colors.textSecondary, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${packet.latitude.toStringAsFixed(5)}, ${packet.longitude.toStringAsFixed(5)}',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onNavigateToMap(packet.latitude, packet.longitude);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map, color: colors.textOnAccent, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'VIEW',
                        style: TextStyle(
                          color: colors.textOnAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
