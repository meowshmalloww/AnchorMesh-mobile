/// SOS Emergency Page
/// Main UI for initiating and managing SOS alerts

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../models/sos_alert.dart';
import '../models/device_info.dart';
import '../services/sos/sos_manager.dart';

/// Broadcast mode selection
enum BroadcastMode { legacy, extended }

class SOSPage extends StatefulWidget {
  const SOSPage({super.key});

  @override
  State<SOSPage> createState() => _SOSPageState();
}

class _SOSPageState extends State<SOSPage> with TickerProviderStateMixin {
  String _locationMessage = "Tap below to get current location";
  bool _isLoading = false;
  bool _isInitializing = true;

  // BLE Broadcast State
  BroadcastMode _selectedMode = BroadcastMode.legacy;
  EmergencyType _selectedEmergencyType = EmergencyType.other;
  final TextEditingController _messageController = TextEditingController();

  // SOS Manager
  late SOSManager _sosManager;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _sosManager = SOSManager(
      config: const SOSManagerConfig(
        serverBaseUrl: 'http://localhost:3000', // Update with your server URL
      ),
    );

    // Create local device info
    final deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    final localDevice = LocalDevice(
      deviceId: deviceId,
      platform: DevicePlatform.ios, // or android based on platform
      appVersion: '1.0.0',
      bleCapabilities: BleCapabilities(
        supportsExtended: _selectedMode == BroadcastMode.extended,
      ),
    );

    await _sosManager.initialize(localDevice);

    // Listen to state changes
    _sosManager.addListener(_onSOSStateChanged);

    if (mounted) {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  void _onSOSStateChanged() {
    if (!mounted) return;

    final state = _sosManager.state;

    // Update animation based on SOS state
    if (state.isActive) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }

    setState(() {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _messageController.dispose();
    _sosManager.removeListener(_onSOSStateChanged);
    _sosManager.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _locationMessage = "Fetching location...";
    });

    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _locationMessage = "Location services are disabled.";
          _isLoading = false;
        });
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _locationMessage = "Location permissions are denied";
            _isLoading = false;
          });
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _locationMessage =
              "Location permissions are permanently denied.";
          _isLoading = false;
        });
      }
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _locationMessage =
              "Lat: ${position.latitude.toStringAsFixed(4)}, Long: ${position.longitude.toStringAsFixed(4)}";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationMessage = "Error getting location: $e";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleSOS() async {
    if (_sosManager.state.isActive) {
      await _sosManager.cancelSOS();
      _showSnackBar('SOS Cancelled');
    } else {
      // Show emergency type selection if not already set
      await _showEmergencyTypeDialog();
    }
  }

  Future<void> _showEmergencyTypeDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Start SOS Alert'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select Emergency Type:'),
              const SizedBox(height: 12),
              ...EmergencyType.values.map((type) => RadioListTile<EmergencyType>(
                    title: Text(type.displayName),
                    value: type,
                    groupValue: _selectedEmergencyType,
                    onChanged: (value) {
                      setState(() {
                        _selectedEmergencyType = value!;
                      });
                      Navigator.of(context).pop(true);
                    },
                    dense: true,
                  )),
              const SizedBox(height: 16),
              TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: 'Additional Message (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Describe your emergency...',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Start SOS', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true) {
      await _startSOS();
    }
  }

  Future<void> _startSOS() async {
    final alert = await _sosManager.initiateSOS(
      emergencyType: _selectedEmergencyType,
      message: _messageController.text.isNotEmpty
          ? _messageController.text
          : null,
    );

    if (alert != null) {
      _showSnackBar('SOS Alert Initiated');
    } else if (_sosManager.state.hasError) {
      _showSnackBar(_sosManager.state.errorMessage ?? 'Failed to start SOS');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: const Text("SOS Emergency")),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing services...'),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final state = _sosManager.state;
    final isBroadcasting = state.isActive;

    return Scaffold(
      appBar: AppBar(
        title: const Text("SOS Emergency"),
        actions: [
          // Status indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildStatusIndicator(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Connectivity Banner
            _buildConnectivityBanner(),
            const SizedBox(height: 20),

            // Main SOS Button
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: isBroadcasting ? _pulseAnimation.value : 1.0,
                  child: GestureDetector(
                    onTap: _toggleSOS,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        color: isBroadcasting ? Colors.redAccent : Colors.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withAlpha(
                              isBroadcasting ? 150 : 100,
                            ),
                            blurRadius: isBroadcasting ? 30 : 20,
                            spreadRadius: isBroadcasting ? 10 : 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isBroadcasting ? Icons.stop : Icons.sensors,
                              size: 40,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isBroadcasting ? "STOP" : "SOS",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isBroadcasting)
                              Text(
                                _getStatusText(state),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // Status Info
            if (isBroadcasting) ...[
              const SizedBox(height: 20),
              _buildStatusCard(state),
            ],

            const SizedBox(height: 40),

            // Location Section
            _buildLocationSection(isDark, textColor, subTextColor),

            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 20),

            // BLE Mode Selection
            Text(
              "Bluetooth Broadcast Mode",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Select the type of signal to broadcast when SOS is active.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: subTextColor),
            ),
            const SizedBox(height: 20),

            _buildCustomRadio(
              context,
              title: "Standard Broadcast (BLE 4.x)",
              description:
                  "Compatible with almost all smartphones. Sends a basic signal on 3 primary channels (37, 38, 39). Best for maximum reach.",
              value: BroadcastMode.legacy,
            ),
            const SizedBox(height: 15),
            _buildCustomRadio(
              context,
              title: "Enhanced Broadcast (BLE 5.0+)",
              description:
                  "Sends larger data packets using secondary channels. Best for rich sensor data or asset tracking. Requires newer devices to detect.",
              value: BroadcastMode.extended,
            ),

            const SizedBox(height: 30),

            // Mesh Network Info
            _buildMeshNetworkInfo(),

            const SizedBox(height: 30),

            // Received Alerts
            if (_sosManager.receivedAlerts.isNotEmpty) ...[
              _buildReceivedAlertsSection(textColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final connectivity = _sosManager.connectivityService.currentState;
    final hasInternet = connectivity.hasInternet;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasInternet ? Colors.green : Colors.orange,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          hasInternet ? 'Online' : 'Mesh',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildConnectivityBanner() {
    final connectivity = _sosManager.connectivityService.currentState;

    if (connectivity.hasInternet) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No Internet Connection',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'SOS will be relayed via Bluetooth mesh to reach emergency services.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(SOSManagerState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatusItem(
                icon: Icons.people,
                value: '${state.peersReached}',
                label: 'Peers Reached',
              ),
              _buildStatusItem(
                icon: Icons.cloud,
                value: state.serverReached ? 'Yes' : 'No',
                label: 'Server Reached',
                color: state.serverReached ? Colors.green : Colors.orange,
              ),
            ],
          ),
          if (state.activeAlert != null) ...[
            const Divider(height: 24),
            Text(
              'Emergency: ${state.activeAlert!.emergencyType.displayName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (state.activeAlert!.message != null)
              Text(
                state.activeAlert!.message!,
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusItem({
    required IconData icon,
    required String value,
    required String label,
    Color? color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color ?? Colors.red),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.red,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  String _getStatusText(SOSManagerState state) {
    switch (state.sosState) {
      case SosState.initiating:
        return 'Initiating...';
      case SosState.broadcasting:
        return 'Broadcasting...';
      case SosState.delivered:
        return 'Delivered to server';
      case SosState.acknowledged:
        return 'Acknowledged';
      default:
        return '';
    }
  }

  Widget _buildLocationSection(bool isDark, Color textColor, Color subTextColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            "Current Location",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _locationMessage,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: subTextColor),
          ),
          const SizedBox(height: 15),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _getCurrentLocation,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(
              _isLoading ? "Fetching..." : "Refresh Location",
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeshNetworkInfo() {
    final meshStatus = _sosManager.bleMeshService.getStatus();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
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
              const Icon(Icons.bluetooth, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                'Mesh Network Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMeshStat('Peers', meshStatus['totalPeers'].toString()),
              _buildMeshStat(
                  'Connected', meshStatus['connectedPeers'].toString()),
              _buildMeshStat(
                  'With Internet', meshStatus['peersWithInternet'].toString()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeshStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildReceivedAlertsSection(Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              'Nearby Alerts (${_sosManager.receivedAlerts.length})',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._sosManager.receivedAlerts.take(5).map((alert) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  _getEmergencyIcon(alert.emergencyType),
                  color: Colors.red,
                ),
                title: Text(alert.emergencyType.displayName),
                subtitle: Text(
                  'Hops: ${alert.hopCount} | ${_formatTime(alert.originatedAt)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      _sosManager.dismissReceivedAlert(alert.messageId),
                ),
              ),
            )),
      ],
    );
  }

  IconData _getEmergencyIcon(EmergencyType type) {
    switch (type) {
      case EmergencyType.medical:
        return Icons.medical_services;
      case EmergencyType.fire:
        return Icons.local_fire_department;
      case EmergencyType.security:
        return Icons.security;
      case EmergencyType.naturalDisaster:
        return Icons.storm;
      case EmergencyType.accident:
        return Icons.car_crash;
      case EmergencyType.other:
        return Icons.warning;
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildCustomRadio(
    BuildContext context, {
    required String title,
    required String description,
    required BroadcastMode value,
  }) {
    final isSelected = _selectedMode == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBroadcasting = _sosManager.state.isActive;

    return InkWell(
      onTap: isBroadcasting
          ? null
          : () {
              setState(() {
                _selectedMode = value;
              });
            },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.blue.withAlpha(40) : Colors.blue.withAlpha(20))
              : (isDark ? Colors.grey[900] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.transparent,
            width: 2,
          ),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: isSelected ? Colors.blue : Colors.grey,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
