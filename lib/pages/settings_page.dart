import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/packet_store.dart';
import '../services/offline_map_service.dart';
import '../services/ble_service.dart';
import '../services/connectivity_service.dart';

/// Battery saving modes for mesh operation
enum BatteryMode {
  /// SOS Active: Always on, max range (6-8 hrs)
  sosActive(
    'SOS Active',
    'Always scanning, maximum reach',
    0, // Always on
    0, // No sleep
    7, // ~6-8 hrs
    'Max reaction time',
  ),

  /// Bridge Mode: 30s on, 30s off (12+ hrs)
  bridge(
    'Bridge Mode',
    '30s on / 30s off, balanced',
    30,
    30,
    12,
    'Fast updates',
  ),

  /// Battery Saver: 1 min on, 1 min off (24+ hrs)
  batterySaver(
    'Battery Saver',
    '1 min on / 1 min off, efficiency',
    60,
    60,
    24,
    'Power efficient',
  ),

  /// Custom: User-defined intervals
  custom(
    'Custom',
    'Set your own intervals',
    30, // Default
    30, // Default
    0, // Depends
    'Customizable',
  );

  final String label;
  final String description;
  final int scanSeconds;
  final int sleepSeconds;
  final int estimatedBatteryHours;
  final String reactionTime;

  const BatteryMode(
    this.label,
    this.description,
    this.scanSeconds,
    this.sleepSeconds,
    this.estimatedBatteryHours,
    this.reactionTime,
  );
}

/// BLE Version options
enum BLEVersion {
  legacy('BLE 4.x (Legacy)', 'Compatible with older devices'),
  modern('BLE 5.x', 'Extended range, faster transfer');

  final String label;
  final String description;

  const BLEVersion(this.label, this.description);
}

/// Settings page with battery modes and app configuration
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  BatteryMode _batteryMode = BatteryMode.bridge;
  BLEVersion _bleVersion = BLEVersion.modern;
  bool _autoActivateOnDisaster = true;
  bool _autoUploadOnInternet = true;
  bool _showNotifications = true;
  String _userId = '';
  bool _supportsBle5 = true; // Default to true, will be checked on load

  // Custom mode settings
  int _customScanSeconds = 30;
  int _customSleepSeconds = 30;

  // Status info from home page
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
    _loadSettings();
    _setupStatusListeners();
    _loadStatusData();
  }

  void _setupStatusListeners() {
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

  Future<void> _loadStatusData() async {
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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await PacketStore.instance.getUserId();

    // Check BLE 5 support (iOS always supports, Android needs check)
    bool supportsBle5 = true;
    if (Platform.isAndroid) {
      supportsBle5 = await BLEService.instance.supportsBle5();
    }

    // Get saved BLE version, default to legacy if BLE 5 not supported
    var bleVersionIndex = prefs.getInt('bleVersion') ?? 1;
    if (!supportsBle5 && bleVersionIndex == 1) {
      // Force legacy mode if BLE 5 not supported
      bleVersionIndex = 0;
      await prefs.setInt('bleVersion', 0);
    }

    setState(() {
      _batteryMode = BatteryMode.values[prefs.getInt('batteryMode') ?? 1];
      _bleVersion = BLEVersion.values[bleVersionIndex];
      _autoActivateOnDisaster = prefs.getBool('autoActivate') ?? true;
      _autoUploadOnInternet = prefs.getBool('autoUpload') ?? true;
      _showNotifications = prefs.getBool('notifications') ?? true;
      _userId = userId.toRadixString(16).toUpperCase().padLeft(8, '0');
      _customScanSeconds = prefs.getInt('customScan') ?? 30;
      _customSleepSeconds = prefs.getInt('customSleep') ?? 30;
      _supportsBle5 = supportsBle5;
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
        onRefresh: _loadStatusData,
        child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Alert banner
          if (_alertLevel != AlertLevel.peace)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: _buildAlertBanner(),
            ),

          // Status Section
          _buildSectionCard(
            title: 'Status',
            icon: Icons.dashboard,
            iconColor: Colors.blue,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _buildStatusRow(
                      icon: Icons.bluetooth,
                      title: 'Mesh Status',
                      value: _getBleStatusText(),
                      color: _getBleStatusColor(),
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(
                      icon: Icons.sensors,
                      title: 'Active SOS Signals',
                      value: _activeSosCount.toString(),
                      color: _activeSosCount > 0 ? Colors.red : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    _buildStatusRow(
                      icon: Icons.cloud,
                      title: 'Internet',
                      value: _isOnline ? 'Connected' : 'Offline',
                      color: _isOnline ? Colors.green : Colors.orange,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Global Alerts Section
          _buildSectionCard(
            title: 'Global Alerts',
            icon: Icons.warning_amber,
            iconColor: Colors.orange,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: _buildGlobalAlerts(),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Battery Mode Section
          _buildSectionCard(
            title: 'Battery Mode',
            icon: Icons.battery_charging_full,
            iconColor: Colors.green,
            children: [
              ...BatteryMode.values.map(
                (mode) => _buildBatteryModeOption(mode),
              ),
              // Custom sliders if custom mode selected
              if (_batteryMode == BatteryMode.custom) _buildCustomSliders(),
            ],
          ),

          const SizedBox(height: 12),

          // BLE Version Section
          _buildSectionCard(
            title: 'Bluetooth',
            icon: Icons.bluetooth,
            iconColor: Colors.blue,
            children: [
              // Only show BLE 5.x option if device supports it
              ...BLEVersion.values
                  .where((v) => v == BLEVersion.legacy || _supportsBle5)
                  .map((version) => _buildBLEVersionOption(version)),
              if (!_supportsBle5)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'BLE 5.x is not available on this device',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Automation Section
          _buildSectionCard(
            title: 'Automation',
            icon: Icons.auto_mode,
            iconColor: Colors.orange,
            children: [
              _buildSwitchTile(
                icon: Icons.warning_amber,
                title: 'Auto-activate on disaster',
                subtitle: 'Start mesh when earthquake detected',
                value: _autoActivateOnDisaster,
                onChanged: (value) {
                  setState(() => _autoActivateOnDisaster = value);
                  _saveSetting('autoActivate', value);
                },
              ),
              _buildSwitchTile(
                icon: Icons.cloud_upload,
                title: 'Auto-upload when online',
                subtitle: 'Sync SOS data when internet returns',
                value: _autoUploadOnInternet,
                onChanged: (value) {
                  setState(() => _autoUploadOnInternet = value);
                  _saveSetting('autoUpload', value);
                },
              ),
              _buildSwitchTile(
                icon: Icons.notifications,
                title: 'Show notifications',
                subtitle: 'Alert when SOS signals received',
                value: _showNotifications,
                onChanged: (value) {
                  setState(() => _showNotifications = value);
                  _saveSetting('notifications', value);
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Device Info Section
          _buildSectionCard(
            title: 'Device',
            icon: Icons.phone_android,
            iconColor: Colors.purple,
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                title: const Text('Device ID'),
                subtitle: Text(
                  _userId,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _userId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Device ID copied')),
                    );
                  },
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
                title: const Text('Clear local data'),
                subtitle: const Text('Remove all cached SOS packets'),
                onTap: _showClearDataDialog,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Packet Info Section
          _buildSectionCard(
            title: 'SOS Packet Info',
            icon: Icons.info,
            iconColor: Colors.teal,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '21-byte Packet Structure:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _buildPacketRow('0-1', 'Header', '0xFFFF'),
                    _buildPacketRow('2-5', 'User ID', '4B random'),
                    _buildPacketRow('6-7', 'Sequence', '2B counter'),
                    _buildPacketRow('8-11', 'Latitude', '4B ×10⁷'),
                    _buildPacketRow('12-15', 'Longitude', '4B ×10⁷'),
                    _buildPacketRow('16', 'Status', '1B code'),
                    _buildPacketRow('17-20', 'Timestamp', '4B Unix'),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // About Section
          _buildSectionCard(
            title: 'About',
            icon: Icons.info_outline,
            iconColor: Colors.grey,
            children: [
              const ListTile(
                leading: Icon(Icons.verified, color: Colors.green),
                title: Text('Version'),
                subtitle: Text('1.0.0'),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline, color: Colors.blue),
                title: const Text('How it works'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showHowItWorksDialog(context),
              ),
            ],
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

  Widget _buildStatusRow({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
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

  Widget _buildGlobalAlerts() {
    // Get cached alerts from disaster monitor
    final cachedNOAA = _disasterMonitor.cachedNOAAResult;
    final hasEarthquake = _disasterMonitor.cachedUSGSResult ?? false;

    if (cachedNOAA == null && !hasEarthquake) {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No Active Alerts',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'All systems normal',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (hasEarthquake)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange),
            ),
            child: Row(
              children: [
                const Icon(Icons.public, color: Colors.orange, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Earthquake Alert',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      Text(
                        'Significant earthquake detected (M6.0+)',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (cachedNOAA != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning, color: Colors.red, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cachedNOAA['event'] ?? 'Weather Alert',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      Text(
                        cachedNOAA['severity'] ?? 'Severe',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
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

  Widget _buildPacketRow(String bytes, String field, String size) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              bytes,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontFamily: 'monospace',
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(field, style: const TextStyle(fontSize: 12)),
          ),
          Text(size, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildCustomSliders() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Scan Duration',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                '${_customScanSeconds}s',
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: _customScanSeconds.toDouble(),
            min: 5,
            max: 120,
            divisions: 23,
            onChanged: (v) {
              setState(() => _customScanSeconds = v.round());
              _saveSetting('customScan', v.round());
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Sleep Duration',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                '${_customSleepSeconds}s',
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: _customSleepSeconds.toDouble(),
            min: 5,
            max: 120,
            divisions: 23,
            onChanged: (v) {
              setState(() => _customSleepSeconds = v.round());
              _saveSetting('customSleep', v.round());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey.withAlpha(30),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildBatteryModeOption(BatteryMode mode) {
    final isSelected = _batteryMode == mode;
    final color = mode == BatteryMode.sosActive
        ? Colors.red
        : mode == BatteryMode.batterySaver
        ? Colors.green
        : mode == BatteryMode.custom
        ? Colors.purple
        : Colors.blue;

    return InkWell(
      onTap: () {
        setState(() => _batteryMode = mode);
        _saveSetting('batteryMode', mode.index);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? color : Colors.grey,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        mode.label,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (mode.estimatedBatteryHours > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '~${mode.estimatedBatteryHours}h',
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mode.description,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBLEVersionOption(BLEVersion version) {
    final isSelected = _bleVersion == version;
    final color = version == BLEVersion.legacy ? Colors.orange : Colors.blue;

    return InkWell(
      onTap: () {
        setState(() => _bleVersion = version);
        _saveSetting('bleVersion', version.index);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? color : Colors.grey,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    version.label,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    version.description,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            if (version == BLEVersion.modern)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Recommended',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Data?'),
        content: const Text(
          'This will remove all cached SOS packets and offline map data. Your device ID will remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);

              await PacketStore.instance.clearAllData();
              await OfflineMapService.instance.clearCache();

              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('Data cleared successfully')),
              );
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showHowItWorksDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How Mesh SOS Works'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1. You send an SOS',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Your phone broadcasts via Bluetooth'),
              SizedBox(height: 12),
              Text(
                '2. Phones relay your message',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Nearby phones pick up and rebroadcast'),
              SizedBox(height: 12),
              Text(
                '3. Message reaches rescuers',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('When any phone gets internet, your SOS uploads'),
              SizedBox(height: 12),
              Text(
                '4. Even without internet',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Rescuers with the app can see your location directly'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
