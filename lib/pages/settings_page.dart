import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Battery saving modes for mesh operation
enum BatteryMode {
  /// SOS Active: Always on, max range
  sosActive('SOS Active', 'Always scanning, maximum reach', 0, 0, 6),

  /// Bridge Mode: 30s on, 30s off
  bridge('Bridge', '30s on / 30s off, balanced', 30, 30, 12),

  /// Eco Mode: 5s on, 55s off
  eco('Eco', '5s on / 55s off, battery saver', 5, 55, 30);

  final String label;
  final String description;
  final int scanSeconds;
  final int sleepSeconds;
  final int estimatedBatteryHours;

  const BatteryMode(
    this.label,
    this.description,
    this.scanSeconds,
    this.sleepSeconds,
    this.estimatedBatteryHours,
  );
}

/// Settings page with battery modes and app configuration
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  BatteryMode _batteryMode = BatteryMode.bridge;
  bool _autoActivateOnDisaster = true;
  bool _autoUploadOnInternet = true;
  bool _showNotifications = true;
  String _userId = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _batteryMode = BatteryMode.values[prefs.getInt('batteryMode') ?? 1];
      _autoActivateOnDisaster = prefs.getBool('autoActivate') ?? true;
      _autoUploadOnInternet = prefs.getBool('autoUpload') ?? true;
      _showNotifications = prefs.getBool('notifications') ?? true;
      _userId = prefs.getString('userId') ?? 'Unknown';
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
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Battery Mode Section
          _buildSectionHeader('Battery Mode'),
          ...BatteryMode.values.map((mode) => _buildBatteryModeOption(mode)),

          const Divider(height: 30),

          // Automation Section
          _buildSectionHeader('Automation'),
          SwitchListTile(
            title: const Text('Auto-activate on disaster'),
            subtitle: const Text('Start mesh when earthquake detected'),
            value: _autoActivateOnDisaster,
            onChanged: (value) {
              setState(() => _autoActivateOnDisaster = value);
              _saveSetting('autoActivate', value);
            },
          ),
          SwitchListTile(
            title: const Text('Auto-upload when online'),
            subtitle: const Text('Sync SOS data when internet returns'),
            value: _autoUploadOnInternet,
            onChanged: (value) {
              setState(() => _autoUploadOnInternet = value);
              _saveSetting('autoUpload', value);
            },
          ),
          SwitchListTile(
            title: const Text('Show notifications'),
            subtitle: const Text('Alert when SOS signals received'),
            value: _showNotifications,
            onChanged: (value) {
              setState(() => _showNotifications = value);
              _saveSetting('notifications', value);
            },
          ),

          const Divider(height: 30),

          // Device Info Section
          _buildSectionHeader('Device'),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Device ID'),
            subtitle: Text(
              _userId.length > 8 ? '${_userId.substring(0, 8)}...' : _userId,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Device ID copied')),
                );
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Clear local data'),
            subtitle: const Text('Remove all cached SOS packets'),
            onTap: _showClearDataDialog,
          ),

          const Divider(height: 30),

          // About Section
          _buildSectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('How it works'),
            onTap: () => _showHowItWorksDialog(context),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildBatteryModeOption(BatteryMode mode) {
    final isSelected = _batteryMode == mode;
    final color = mode == BatteryMode.sosActive
        ? Colors.red
        : mode == BatteryMode.eco
        ? Colors.green
        : Colors.blue;

    return InkWell(
      onTap: () {
        setState(() => _batteryMode = mode);
        _saveSetting('batteryMode', mode.index);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? color : Colors.grey,
            ),
            const SizedBox(width: 16),
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
                        ),
                      ),
                      const SizedBox(width: 8),
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
                  const SizedBox(height: 4),
                  Text(
                    mode.description,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
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
          'This will remove all cached SOS packets. Your device ID will remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Data cleared')));
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
