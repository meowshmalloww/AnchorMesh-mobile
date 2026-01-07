import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

enum BroadcastMode { legacy, extended }

class SOSPage extends StatefulWidget {
  const SOSPage({super.key});

  @override
  State<SOSPage> createState() => _SOSPageState();
}

class _SOSPageState extends State<SOSPage> with TickerProviderStateMixin {
  String _locationMessage = "Tap below to get current location";
  bool _isLoading = false;

  // BLE Broadcast State
  BroadcastMode _selectedMode = BroadcastMode.legacy;
  bool _isBroadcasting = false;
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
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _locationMessage = "Fetching location...";
    });

    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
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
              "Location permissions are permanently denied, we cannot request permissions.";
          _isLoading = false;
        });
      }
      return;
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
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

  void _toggleBroadcast() {
    setState(() {
      _isBroadcasting = !_isBroadcasting;
    });
    if (_isBroadcasting) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      appBar: AppBar(title: const Text("SOS Emergency")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // SOS Button Section
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                debugPrint("SOS Pressed");
              },
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withAlpha(100),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    "SOS",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Location Section
            Container(
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
            ),

            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 20),

            // BLE Section
            Text(
              "Bluetooth Broadcast",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 20),

            // Mode Selection
            _buildRadioOption(
              context,
              title: "Legacy Advertising (BLE 4.x)",
              description:
                  "• 2-byte header (Length & Type)\n• Channels: 37, 38, 39\n• Payload: ~31 bytes\n• Supported by nearly all devices.\n• Best for: Simple, basic broadcasting.",
              value: BroadcastMode.legacy,
            ),
            const SizedBox(height: 15),
            _buildRadioOption(
              context,
              title: "Extended Advertising (BLE 5.0+)",
              description:
                  "• Uses primary channels for header, data on 37 secondary channels.\n• Payload: Up to 255 bytes (1600+ with chaining).\n• Requires BLE 5.0+ scanner.\n• Best for: Rich sensor data, asset tracking, firmware.",
              value: BroadcastMode.extended,
            ),

            const SizedBox(height: 30),

            // Broadcast Button
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isBroadcasting ? _pulseAnimation.value : 1.0,
                  child: child,
                );
              },
              child: ElevatedButton.icon(
                onPressed: _toggleBroadcast,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isBroadcasting
                      ? Colors.blueAccent
                      : Colors.grey[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: _isBroadcasting ? 10 : 2,
                ),
                icon: Icon(
                  _isBroadcasting ? Icons.bluetooth_searching : Icons.bluetooth,
                ),
                label: Text(
                  _isBroadcasting ? "STOP BROADCASTING" : "START BROADCAST",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (_isBroadcasting) ...[
              const SizedBox(height: 10),
              Text(
                "Broadcasting ${_selectedMode == BroadcastMode.legacy ? "Legacy" : "Extended"} Signal...",
                style: const TextStyle(
                  color: Colors.blueAccent,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRadioOption(
    BuildContext context, {
    required String title,
    required String description,
    required BroadcastMode value,
  }) {
    final isSelected = _selectedMode == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark ? Colors.blue.withAlpha(50) : Colors.blue.withAlpha(30))
            : (isDark ? Colors.grey[900] : Colors.grey[100]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.blue : Colors.transparent,
          width: 2,
        ),
      ),
      child: RadioListTile<BroadcastMode>(
        value: value,
        groupValue: _selectedMode,
        onChanged: _isBroadcasting
            ? null // Disable changing during broadcast
            : (BroadcastMode? val) {
                setState(() {
                  _selectedMode = val!;
                });
              },
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            description,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
        activeColor: Colors.blue,
      ),
    );
  }
}
