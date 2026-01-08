import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/connectivity_service.dart';

/// Home page with mesh status overview and quick actions
class HomePage extends StatefulWidget {
  final Function(int)? onTabChange;

  const HomePage({super.key, this.onTabChange});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BLEService _bleService = BLEService.instance;
  final DisasterMonitor _disasterMonitor = DisasterMonitor.instance;
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
    _alertSub = _disasterMonitor.levelStream.listen((level) {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh SOS'),
        centerTitle: true,
        actions: [
          // Connection indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              _isOnline ? Icons.wifi : Icons.wifi_off,
              color: _isOnline ? Colors.green : Colors.red,
              size: 20,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Alert banner
            if (_alertLevel != AlertLevel.peace) _buildAlertBanner(),

            // Status cards
            _buildStatusCard(
              icon: Icons.bluetooth,
              title: 'Mesh Status',
              value: _getBleStatusText(),
              color: _getBleStatusColor(),
            ),
            const SizedBox(height: 12),
            _buildStatusCard(
              icon: Icons.sensors,
              title: 'Active SOS Signals',
              value: _activeSosCount.toString(),
              color: _activeSosCount > 0 ? Colors.red : Colors.grey,
            ),
            const SizedBox(height: 12),
            _buildStatusCard(
              icon: Icons.cloud,
              title: 'Internet',
              value: _isOnline ? 'Connected' : 'Offline',
              color: _isOnline ? Colors.green : Colors.orange,
            ),

            const SizedBox(height: 30),

            // Quick actions
            Text(
              'QUICK ACTIONS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.sos,
                    label: 'Send SOS',
                    color: Colors.red,
                    onTap: () => _navigateToSOS(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.map,
                    label: 'View Map',
                    color: Colors.blue,
                    onTap: () => _navigateToMap(context),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            // Info section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'How it works',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '• Your phone broadcasts SOS via Bluetooth\n'
                    '• Nearby phones relay your message\n'
                    '• Works even without internet\n'
                    '• Keep the app open for best results',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.grey[600],
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

  Widget _buildAlertBanner() {
    final color = _alertLevel == AlertLevel.disaster
        ? Colors.red
        : Colors.orange;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _alertLevel.label.toUpperCase(),
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                Text(
                  _alertLevel.description,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getBleStatusText() {
    switch (_bleState) {
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

  Color _getBleStatusColor() {
    switch (_bleState) {
      case BLEConnectionState.meshActive:
        return Colors.green;
      case BLEConnectionState.broadcasting:
      case BLEConnectionState.scanning:
        return Colors.blue;
      case BLEConnectionState.bluetoothOff:
      case BLEConnectionState.unavailable:
        return Colors.red;
      case BLEConnectionState.idle:
        return Colors.grey;
    }
  }

  void _navigateToSOS(BuildContext context) {
    widget.onTabChange?.call(3); // SOS tab index
  }

  void _navigateToMap(BuildContext context) {
    widget.onTabChange?.call(1); // Map tab index
  }
}
