import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:torch_light/torch_light.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/morse_code_translator.dart';

class OfflineUtilityPage extends StatefulWidget {
  const OfflineUtilityPage({super.key});

  @override
  State<OfflineUtilityPage> createState() => _OfflineUtilityPageState();
}

class _OfflineUtilityPageState extends State<OfflineUtilityPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Flashlight State
  bool _isTorchAvailable = false;

  // Compass State
  double? _heading = 0;

  // Strobe State
  final TextEditingController _messageController = TextEditingController();
  bool _isStrobing = false;
  double _strobeSpeed = 1.0; // Seconds per unit (approx) - Adjustable
  Timer? _strobeTimer;

  // Bluetooth Scanner State
  bool _isScanning = false;
  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkTorchAvailability();

    // Compass Listener
    FlutterCompass.events?.listen((event) {
      if (mounted) {
        setState(() {
          _heading = event.heading;
        });
      }
    });
  }

  Future<void> _checkTorchAvailability() async {
    try {
      _isTorchAvailable = await TorchLight.isTorchAvailable();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Torch availability check failed: $e");
      _isTorchAvailable = false;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    _stopStrobe();
    _stopBluetoothScan();
    _scanSubscription?.cancel();
    super.dispose();
  }

  void _toggleStrobe() {
    if (_isStrobing) {
      _stopStrobe();
    } else {
      _startStrobe();
    }
  }

  void _stopStrobe() async {
    _strobeTimer?.cancel();
    _strobeTimer = null;

    // Ensure off
    try {
      await TorchLight.disableTorch();
    } catch (e) {
      debugPrint("Error turning off torch: $e");
    }

    if (mounted) {
      setState(() {
        _isStrobing = false;
      });
    }
  }

  Future<void> _startStrobe() async {
    if (!_isTorchAvailable) {
      await _checkTorchAvailability();
      if (!mounted) return;

      if (!_isTorchAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Flashlight not available")),
        );
        return;
      }
    }

    String text = _messageController.text.trim();
    if (text.isEmpty) text = "SOS";

    String morse = MorseCodeTranslator.textToMorse(text);
    debugPrint("Strobing: $text -> $morse");

    setState(() {
      _isStrobing = true;
    });

    List<_StrobeAction> actions = [];
    double unit = 200 * (1 / _strobeSpeed); // base 200ms

    for (int i = 0; i < morse.length; i++) {
      String char = morse[i];
      if (char == '.') {
        actions.add(_StrobeAction(true, (unit * 1).toInt()));
        actions.add(_StrobeAction(false, (unit * 1).toInt()));
      } else if (char == '-') {
        actions.add(_StrobeAction(true, (unit * 3).toInt()));
        actions.add(_StrobeAction(false, (unit * 1).toInt()));
      } else if (char == ' ') {
        actions.add(_StrobeAction(false, (unit * 2).toInt()));
      } else if (char == '/') {
        actions.add(_StrobeAction(false, (unit * 6).toInt()));
      }
    }
    actions.add(_StrobeAction(false, (unit * 7).toInt()));

    _runStrobeSequence(actions);
  }

  Future<void> _runStrobeSequence(List<_StrobeAction> actions) async {
    if (!_isStrobing) return;

    for (var action in actions) {
      if (!_isStrobing) break;

      if (action.isOn) {
        try {
          await TorchLight.enableTorch();
        } catch (_) {}
      }

      await Future.delayed(Duration(milliseconds: action.duration));

      if (action.isOn) {
        try {
          await TorchLight.disableTorch();
        } catch (_) {}
      }
    }

    if (_isStrobing) {
      // Loop
      // Add small delay to prevent tight loop if sequence is empty or something
      if (actions.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 1000));
      }
      _runStrobeSequence(actions);
    }
  }

  // Bluetooth Scanner Methods
  Future<void> _startBluetoothScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _scanResults = [];
    });

    try {
      // Check if Bluetooth is on
      if (await FlutterBluePlus.isSupported == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Bluetooth not supported on this device")),
          );
        }
        setState(() => _isScanning = false);
        return;
      }

      // Listen to scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            _scanResults = results;
            // Sort by signal strength (strongest first)
            _scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));
          });
        }
      });

      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );

      // When scan completes
      await FlutterBluePlus.isScanning.where((val) => val == false).first;

      if (mounted) {
        setState(() => _isScanning = false);
      }
    } catch (e) {
      debugPrint("Bluetooth scan error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Scan error: $e")),
        );
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _stopBluetoothScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint("Error stopping scan: $e");
    }
    if (mounted) {
      setState(() => _isScanning = false);
    }
  }

  String _getProximityFromRssi(int rssi) {
    if (rssi >= -50) return "Immediate (<1m)";
    if (rssi >= -60) return "Very Near (1-2m)";
    if (rssi >= -70) return "Near (2-5m)";
    if (rssi >= -80) return "Medium (5-10m)";
    if (rssi >= -90) return "Far (10-20m)";
    return "Very Far (>20m)";
  }

  Color _getProximityColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -60) return Colors.lightGreen;
    if (rssi >= -70) return Colors.yellow.shade700;
    if (rssi >= -80) return Colors.orange;
    if (rssi >= -90) return Colors.deepOrange;
    return Colors.red;
  }

  double _getProximityPercent(int rssi) {
    // Map RSSI from -100 to -30 to 0-100%
    return ((rssi + 100) / 70).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Offline Utilities"),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.black,
          tabs: const [
            Tab(icon: Icon(Icons.explore), text: "Compass"),
            Tab(icon: Icon(Icons.flashlight_on), text: "Strobe SOS"),
            Tab(icon: Icon(Icons.bluetooth_searching), text: "BLE Scanner"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildCompassTab(), _buildStrobeTab(), _buildBluetoothTab()],
      ),
    );
  }

  Widget _buildCompassTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "${(_heading ?? 0).toStringAsFixed(0)}°",
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Transform.rotate(
            angle: ((_heading ?? 0) * (math.pi / 180) * -1),
            child: const Icon(Icons.explore, size: 200, color: Colors.blueGrey),
          ),
          const SizedBox(height: 20),
          const Text(
            "Align top of phone",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildStrobeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          TextField(
            controller: _messageController,
            decoration: const InputDecoration(
              labelText: "Enter Message (Default: SOS)",
              border: OutlineInputBorder(),
              hintText: "SOS",
            ),
          ),
          const SizedBox(height: 20),
          Text("Speed: ${_strobeSpeed.toStringAsFixed(1)}x"),
          Slider(
            value: _strobeSpeed,
            min: 0.1,
            max: 3.0,
            divisions: 29,
            label: _strobeSpeed.toStringAsFixed(1),
            onChanged: (val) {
              setState(() {
                _strobeSpeed = val;
              });
            },
          ),
          const SizedBox(height: 40),

          GestureDetector(
            onTap: _toggleStrobe,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: _isStrobing ? Colors.red : Colors.grey[800],
                shape: BoxShape.circle,
                boxShadow: [
                  if (_isStrobing)
                    BoxShadow(
                      color: Colors.red.withAlpha(150),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.power_settings_new,
                size: 60,
                color: _isStrobing ? Colors.white : Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _isStrobing ? "STROBING..." : "TAP TO START",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildBluetoothTab() {
    return Column(
      children: [
        // Scan button
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? _stopBluetoothScan : _startBluetoothScan,
                  icon: Icon(_isScanning ? Icons.stop : Icons.bluetooth_searching),
                  label: Text(_isScanning ? "Stop Scan" : "Start Scan"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isScanning ? Colors.red : Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "${_scanResults.length} devices",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        if (_isScanning)
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: LinearProgressIndicator(),
          ),

        // Device list
        Expanded(
          child: _scanResults.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isScanning
                            ? "Scanning for devices..."
                            : "Tap 'Start Scan' to find nearby Bluetooth devices",
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _scanResults.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, index) {
                    final result = _scanResults[index];
                    return _buildDeviceCard(result);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(ScanResult result) {
    final device = result.device;
    final advertisementData = result.advertisementData;
    final rssi = result.rssi;
    final proximity = _getProximityFromRssi(rssi);
    final proximityColor = _getProximityColor(rssi);
    final proximityPercent = _getProximityPercent(rssi);

    final deviceName = advertisementData.advName.isNotEmpty
        ? advertisementData.advName
        : device.platformName.isNotEmpty
            ? device.platformName
            : "Unknown Device";

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: proximityColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            advertisementData.connectable ? Icons.bluetooth : Icons.bluetooth_disabled,
            color: proximityColor,
          ),
        ),
        title: Text(
          deviceName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: proximityColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    proximity,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "$rssi dBm",
                  style: TextStyle(
                    color: proximityColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: proximityPercent,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(proximityColor),
                minHeight: 6,
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow("Device ID", device.remoteId.str),
                _buildDetailRow("Connectable", advertisementData.connectable ? "Yes" : "No"),
                _buildDetailRow("TX Power", advertisementData.txPowerLevel != null
                    ? "${advertisementData.txPowerLevel} dBm"
                    : "N/A"),
                _buildDetailRow("RSSI", "$rssi dBm"),
                _buildDetailRow("Estimated Distance", proximity),

                if (advertisementData.serviceUuids.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    "Service UUIDs:",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  ...advertisementData.serviceUuids.map((uuid) => Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 2),
                        child: Text(
                          uuid.str,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        ),
                      )),
                ],

                if (advertisementData.serviceData.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    "Service Data:",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  ...advertisementData.serviceData.entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key.str,
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            ),
                            Text(
                              "Data: ${entry.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}",
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )),
                ],

                if (advertisementData.manufacturerData.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    "Manufacturer Data:",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  ...advertisementData.manufacturerData.entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "ID: 0x${entry.key.toRadixString(16).padLeft(4, '0')} (${_getManufacturerName(entry.key)})",
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              "Data: ${entry.value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}",
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getManufacturerName(int id) {
    // Common manufacturer IDs
    const manufacturers = {
      0x004C: "Apple",
      0x0006: "Microsoft",
      0x000F: "Broadcom",
      0x0059: "Nordic Semiconductor",
      0x00E0: "Google",
      0x0075: "Samsung",
      0x0087: "Garmin",
      0x00D2: "Bose",
      0x0310: "Xiaomi",
      0x0157: "Huawei",
      0x0131: "Fitbit",
      0x0499: "Ruuvi",
      0x0822: "Adafruit",
    };
    return manufacturers[id] ?? "Unknown";
  }
}

class _StrobeAction {
  final bool isOn;
  final int duration;
  _StrobeAction(this.isOn, this.duration);
}
