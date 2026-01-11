import 'dart:io';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart'; // Added for LatLng
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart'; // Added for location
import '../services/packet_store.dart';
import '../services/offline_map_service.dart';
import '../services/ble_service.dart';
import '../services/onboarding_service.dart';
import '../models/settings_enums.dart';
import 'alerts_history_page.dart';
import 'region_selection_page.dart';
import 'onboarding_page.dart';
import '../theme_notifier.dart';
import '../widgets/sync_status_widget.dart';

// Re-export for backward compatibility
export '../models/settings_enums.dart';

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
  // ignore: unused_field
  String _userId = ''; // Set during _loadSettings, may be used later
  bool _supportsBle5 = true; // Default to true, will be checked on load

  // Custom mode settings
  int _customScanSeconds = 30;
  int _customSleepSeconds = 30;

  bool _isDownloadingMap = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  bool _autoDownloadMaps = true;
  String _mapStorageSize = 'Calculating...';

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
      _autoDownloadMaps = prefs.getBool('autoDownloadMaps') ?? true;
    });
    _updateStorageStats();
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
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.only(top: topPadding + 12, bottom: 120),
        children: [
          // Display Section
          _buildSectionCard(
            title: 'Display',
            icon: Icons.brightness_6,
            iconColor: Colors.deepPurple,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Expanded(child: Text('Theme Mode')),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('Auto'),
                          icon: Icon(Icons.brightness_auto),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode),
                        ),
                      ],
                      selected: {ThemeNotifier().value},
                      onSelectionChanged: (Set<ThemeMode> newSelection) {
                        setState(() {
                          ThemeNotifier().setTheme(newSelection.first);
                        });
                      },
                      style: ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
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

          // Data & Storage Section (New)
          _buildSectionCard(
            title: 'Data & Storage',
            icon: Icons.storage,
            iconColor: Colors.teal,
            children: [
              // Storage Stats
              // Storage Stats (Custom Row for alignment)
              // Storage Stats
              ListTile(
                leading: const Icon(Icons.sd_storage, color: Colors.blue),
                title: const Text('Map Storage'),
                subtitle: Text(
                  _mapStorageSize,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.blueGrey,
                  ),
                  onPressed: _clearMapCache,
                  tooltip: 'Clear Map Cache',
                ),
              ),

              if (_isDownloadingMap)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _downloadStatus,
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: _downloadProgress),
                    ],
                  ),
                ),

              // Download Actions
              ListTile(
                leading: const Icon(Icons.public, color: Colors.indigo),
                title: const Text('Global Disaster Map'),
                subtitle: const Text(
                  'Whole World (Zoom 0-5)\nNot downloadable by area',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.download),
                enabled: !_isDownloadingMap,
                onTap: _downloadGlobalMap,
              ),
              ListTile(
                leading: const Icon(Icons.place, color: Colors.red),
                title: const Text('Local SOS Map'),
                subtitle: const Text('Download specific area'),
                trailing: const Icon(Icons.download),
                enabled: !_isDownloadingMap,
                onTap: _downloadLocalMap,
              ),

              const Divider(),

              // Legacy Region Selection
              ListTile(
                title: const Text('Custom Region'),
                leading: const Icon(Icons.map),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RegionSelectionPage(),
                    ),
                  );
                },
              ),

              ListTile(
                title: const Text('Alert History'),
                leading: const Icon(Icons.history),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AlertsHistoryPage(),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          _buildSectionCard(
            title: 'Offline Settings',
            icon: Icons.settings_system_daydream,
            iconColor: Colors.teal,
            children: [
              _buildSwitchTile(
                icon: Icons.download_rounded,
                title: 'Auto-download Maps',
                subtitle: 'Update maps on launch',
                value: _autoDownloadMaps,
                onChanged: (val) {
                  setState(() => _autoDownloadMaps = val);
                  _saveSetting('autoDownloadMaps', val);
                },
              ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    'BLE 5.x is not available on this device',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
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

          // Cloud Sync Section
          _buildSectionCard(
            title: 'Cloud Sync',
            icon: Icons.cloud,
            iconColor: Colors.indigo,
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: SyncStatusWidget(compact: false, showSyncButton: true),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Data & Storage Section (New)
          _buildSectionCard(
            title: 'Data & Storage',
            icon: Icons.storage,
            iconColor: Colors.teal,
            children: [
              ListTile(
                leading: const Icon(Icons.history, color: Colors.teal),
                title: const Text('Alert History'),
                subtitle: const Text('View all past SOS signals'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AlertsHistoryPage()),
                ),
              ),

              _buildStorageStats(),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.download_for_offline,
                  color: Colors.blue,
                ),
                title: const Text('Download Offline Region'),
                subtitle: const Text('Select area to save for offline use'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RegionSelectionPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.orange),
                title: const Text('Clear Map Cache'),
                onTap: _showClearMapDialog,
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Clear SOS History'),
                subtitle: const Text('Remove all cached packets'),
                onTap: _showClearHistoryDialog,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Location Section (Moved from SOS)
          _buildSectionCard(
            title: 'Location Reference',
            icon: Icons.location_on,
            iconColor: Colors.red,
            children: [_buildLocationTile()],
          ),

          const SizedBox(height: 12),

          // Packet Info Section
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
                subtitle: Text('v2.6.0'),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline, color: Colors.blue),
                title: const Text('How it works'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showHowItWorksDialog(context),
              ),
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.orange),
                title: const Text('Redo Onboarding'),
                subtitle: const Text('Review permissions and setup again'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await OnboardingService.instance.resetOnboarding();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const OnboardingPage()),
                      (route) => false,
                    );
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 30),
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

  Widget _buildStorageStats() {
    return FutureBuilder<Map<String, int>>(
      future: _getStorageSizes(),
      builder: (context, snapshot) {
        final sosSize = snapshot.data?['sos'] ?? 0;
        final mapSize = snapshot.data?['map'] ?? 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SOS Data',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      '${(sosSize / 1024).toStringAsFixed(1)} KB',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Map Tiles',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      '${(mapSize / 1024 / 1024).toStringAsFixed(1)} MB',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, int>> _getStorageSizes() async {
    final sosSize = await PacketStore.instance.getStorageSize();
    // Use placeholder for map stats for now until true implementation
    final mapStats = await OfflineMapService.instance.getStorageStats();
    final mapSize = mapStats['sizeBytes'] as int? ?? 0;
    return {'sos': sosSize, 'map': mapSize};
  }

  void _showClearMapDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Map Cache?'),
        content: const Text('This will delete all offline map tiles.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final scaffold = ScaffoldMessenger.of(context);
              await OfflineMapService.instance.clearCache();
              if (mounted) {
                nav.pop();
                setState(() {}); // refresh stats
                scaffold.showSnackBar(
                  const SnackBar(content: Text('Map cache cleared')),
                );
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History?'),
        content: const Text('This will delete all SOS packet history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final scaffold = ScaffoldMessenger.of(context);
              await PacketStore.instance.clearAllData();
              if (mounted) {
                nav.pop();
                setState(() {}); // refresh stats
                scaffold.showSnackBar(
                  const SnackBar(content: Text('History cleared')),
                );
              }
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
        title: const Text('How AnchorMesh Works'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1. Activate SOS',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Your phone broadcasts a secure signal via Bluetooth (BLE). No internet required.',
              ),
              SizedBox(height: 12),
              Text(
                '2. Mesh Relay',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Nearby devices act as anchors, picking up and relaying your signal to extend range.',
              ),
              SizedBox(height: 12),
              Text(
                '3. Global Delivery',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'If ANY phone in the mesh has internet, your SOS is uploaded to our servers immediately.',
              ),
              SizedBox(height: 12),
              Text(
                '4. Local Rescue',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Rescuers can track your exact direction and distance without internet using the signal locator.',
              ),
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

  // Location Tile Logic
  Widget _buildLocationTile() {
    return ListTile(
      leading: const Icon(Icons.my_location),
      title: const Text('Current Location'),
      subtitle: FutureBuilder<Position?>(
        future: _getCurrentPosition(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Text('Fetching...');
          }
          if (snapshot.hasError) {
            return const Text('Location unavailable');
          }
          if (snapshot.hasData) {
            return Text(
              '${snapshot.data!.latitude.toStringAsFixed(5)}, ${snapshot.data!.longitude.toStringAsFixed(5)}',
            );
          }
          return const Text('Tap to refresh');
        },
      ),
      trailing: IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: () {
          setState(() {}); // Rebuild to refetch
        },
      ),
    );
  }

  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (e) {
      return null;
    }
  }

  // Offline Map Helpers
  Future<void> _updateStorageStats() async {
    final stats = await OfflineMapService.instance.getStorageStats();
    final bytes = stats['sizeBytes'] as int;
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    final count = stats['tiles'] as int;
    if (mounted) {
      setState(() {
        _mapStorageSize = '$mb MB ($count tiles)';
      });
    }
  }

  Future<void> _clearMapCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Map Cache?'),
        content: const Text('This will delete all offline map tiles.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await OfflineMapService.instance.clearCache();
      _updateStorageStats();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Map cache cleared')));
      }
    }
  }

  Future<void> _downloadGlobalMap() async {
    setState(() {
      _isDownloadingMap = true;
      _downloadStatus = 'Starting global download...';
      _downloadProgress = 0.0;
    });

    try {
      await OfflineMapService.instance.downloadGlobalMap(
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = done / total;
              _downloadStatus =
                  'Downloading Global Map: ${(done / total * 100).toInt()}% ($done/$total)';
            });
          }
        },
        onComplete: () {
          if (mounted) {
            setState(() {
              _isDownloadingMap = false;
              _downloadStatus = 'Download Complete';
            });
            _updateStorageStats();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Global Map Downloaded!')),
            );
          }
        },
        onError: (err) {
          if (mounted) {
            setState(() {
              _isDownloadingMap = false;
              _downloadStatus = 'Error: $err';
            });
          }
        },
      );
    } catch (e) {
      setState(() => _isDownloadingMap = false);
    }
  }

  Future<void> _downloadLocalMap() async {
    setState(() {
      _isDownloadingMap = true;
      _downloadStatus = 'Getting location...';
      _downloadProgress = 0.0;
    });

    try {
      final pos = await _getCurrentPosition();
      if (pos == null) {
        setState(() {
          _isDownloadingMap = false;
          _downloadStatus = 'Location unavailable';
        });
        return;
      }

      await OfflineMapService.instance.downloadLocalMap(
        center: LatLng(pos.latitude, pos.longitude), // Requires latlong2 import
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = done / total;
              _downloadStatus =
                  'Downloading Local Map: ${(done / total * 100).toInt()}% ($done/$total)';
            });
          }
        },
        onComplete: () {
          if (mounted) {
            setState(() {
              _isDownloadingMap = false;
              _downloadStatus = 'Download Complete';
            });
            _updateStorageStats();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Local Map Downloaded!')),
            );
          }
        },
        onError: (err) {},
      );
    } catch (e) {
      setState(() => _isDownloadingMap = false);
    }
  }
}
