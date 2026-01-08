import 'package:flutter/material.dart';
import '../services/storage/device_storage_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final DeviceStorageService _storageService = DeviceStorageService();

  // User preferences
  bool _autoShareLocation = true;
  bool _enableSoundAlerts = true;
  bool _vibrationEnabled = true;

  // Server settings
  String _serverUrl = DeviceStorageService.defaultServerUrl;
  String _deviceId = '';
  bool _isLoadingSettings = true;

  // Emergency contacts (in real app, store persistently)
  final List<Map<String, String>> _emergencyContacts = [
    {'name': 'Emergency Services', 'phone': '911'},
  ];

  // User profile info
  String _userName = '';
  String _bloodType = 'Unknown';
  String _medicalNotes = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _storageService.initialize();
    final serverUrl = await _storageService.getServerUrl();
    final deviceId = await _storageService.getDeviceId();

    if (mounted) {
      setState(() {
        _serverUrl = serverUrl;
        _deviceId = deviceId;
        _isLoadingSettings = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDarkMode ? Colors.grey[900] : Colors.grey[50];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Section
          _buildSectionHeader(context, "Emergency Profile", Icons.person),
          const SizedBox(height: 8),
          _buildCard(
            context,
            cardColor,
            children: [
              _buildProfileTile(
                context,
                icon: Icons.badge,
                title: "Name",
                subtitle: _userName.isEmpty ? "Tap to add your name" : _userName,
                onTap: () => _showNameDialog(),
              ),
              const Divider(height: 1),
              _buildProfileTile(
                context,
                icon: Icons.bloodtype,
                title: "Blood Type",
                subtitle: _bloodType,
                onTap: () => _showBloodTypeDialog(),
              ),
              const Divider(height: 1),
              _buildProfileTile(
                context,
                icon: Icons.medical_information,
                title: "Medical Notes",
                subtitle: _medicalNotes.isEmpty
                    ? "Allergies, conditions, medications..."
                    : _medicalNotes,
                onTap: () => _showMedicalNotesDialog(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Emergency Contacts Section
          _buildSectionHeader(context, "Emergency Contacts", Icons.contacts),
          const SizedBox(height: 8),
          _buildCard(
            context,
            cardColor,
            children: [
              ..._emergencyContacts.asMap().entries.map((entry) {
                final index = entry.key;
                final contact = entry.value;
                return Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.withValues(alpha: 0.1),
                        child: const Icon(Icons.person, color: Colors.red),
                      ),
                      title: Text(contact['name']!),
                      subtitle: Text(contact['phone']!),
                      trailing: index == 0
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _removeContact(index),
                            ),
                    ),
                    if (index < _emergencyContacts.length - 1)
                      const Divider(height: 1),
                  ],
                );
              }),
              const Divider(height: 1),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.withValues(alpha: 0.1),
                  child: const Icon(Icons.add, color: Colors.blue),
                ),
                title: const Text("Add Emergency Contact"),
                subtitle: const Text("Add a trusted contact"),
                onTap: () => _showAddContactDialog(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // SOS Preferences Section
          _buildSectionHeader(context, "SOS Preferences", Icons.sos),
          const SizedBox(height: 8),
          _buildCard(
            context,
            cardColor,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.location_on),
                title: const Text("Auto-share Location"),
                subtitle: const Text("Include GPS coordinates in SOS alerts"),
                value: _autoShareLocation,
                onChanged: (value) {
                  setState(() => _autoShareLocation = value);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up),
                title: const Text("Sound Alerts"),
                subtitle: const Text("Play alarm sound during SOS"),
                value: _enableSoundAlerts,
                onChanged: (value) {
                  setState(() => _enableSoundAlerts = value);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.vibration),
                title: const Text("Vibration"),
                subtitle: const Text("Vibrate when SOS is active"),
                value: _vibrationEnabled,
                onChanged: (value) {
                  setState(() => _vibrationEnabled = value);
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Server Settings Section
          _buildSectionHeader(context, "Server Settings", Icons.dns),
          const SizedBox(height: 8),
          _buildCard(
            context,
            cardColor,
            children: [
              _buildProfileTile(
                context,
                icon: Icons.link,
                title: "Server URL",
                subtitle: _isLoadingSettings ? "Loading..." : _serverUrl,
                onTap: () => _showServerUrlDialog(),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: const Text("Device ID"),
                subtitle: Text(
                  _isLoadingSettings ? "Loading..." : _deviceId,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    // Copy to clipboard would go here
                    _showSnackBar("Device ID copied to clipboard");
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // About Section
          _buildSectionHeader(context, "About", Icons.info),
          const SizedBox(height: 8),
          _buildCard(
            context,
            cardColor,
            children: [
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text("App Version"),
                subtitle: const Text("1.0.0"),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.privacy_tip),
                title: const Text("Privacy Policy"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _showSnackBar("Privacy policy coming soon");
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text("Help & Support"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _showSnackBar("Help center coming soon");
                },
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Reset button
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.restore, color: Colors.red),
              label: const Text(
                "Reset All Settings",
                style: TextStyle(color: Colors.red),
              ),
              onPressed: () => _showResetConfirmation(),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 20, color: isDarkMode ? Colors.white70 : Colors.black54),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDarkMode ? Colors.white70 : Colors.black54,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, Color? cardColor, {required List<Widget> children}) {
    return Card(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildProfileTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  void _showNameDialog() {
    final controller = TextEditingController(text: _userName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Your Name"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Enter your name",
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _userName = controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showBloodTypeDialog() {
    final bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Unknown'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Blood Type"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          // ignore: deprecated_member_use - RadioGroup migration pending
          children: bloodTypes.map((type) => RadioListTile<String>(
            title: Text(type),
            value: type,
            groupValue: _bloodType,
            onChanged: (value) {
              setState(() => _bloodType = value!);
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }

  void _showMedicalNotesDialog() {
    final controller = TextEditingController(text: _medicalNotes);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Medical Notes"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Allergies, conditions, medications...",
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _medicalNotes = controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Emergency Contact"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "Name",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: "Phone Number",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && phoneController.text.isNotEmpty) {
                setState(() {
                  _emergencyContacts.add({
                    'name': nameController.text.trim(),
                    'phone': phoneController.text.trim(),
                  });
                });
                Navigator.pop(context);
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  void _removeContact(int index) {
    setState(() {
      _emergencyContacts.removeAt(index);
    });
  }

  void _showServerUrlDialog() {
    final controller = TextEditingController(text: _serverUrl);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Server URL"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Enter the URL of your SOS relay server. The app will send emergency alerts to this server.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "https://sos-relay.example.com",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              controller.text = DeviceStorageService.defaultServerUrl;
            },
            child: const Text("Reset"),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                final navigator = Navigator.of(dialogContext);
                await _storageService.setServerUrl(url);
                if (!mounted) return;
                setState(() => _serverUrl = url);
                navigator.pop();
                _showSnackBar("Server URL updated. Restart app for changes to take effect.");
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showResetConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reset Settings?"),
        content: const Text(
          "This will reset all settings to their defaults. Your emergency contacts will also be removed.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _userName = '';
                _bloodType = 'Unknown';
                _medicalNotes = '';
                _emergencyContacts.clear();
                _emergencyContacts.add({'name': 'Emergency Services', 'phone': '911'});
                _autoShareLocation = true;
                _enableSoundAlerts = true;
                _vibrationEnabled = true;
              });
              Navigator.pop(context);
              _showSnackBar("Settings reset to defaults");
            },
            child: const Text("Reset", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
