import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:torch_light/torch_light.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildCompassTab(), _buildStrobeTab()],
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
}

class _StrobeAction {
  final bool isOn;
  final int duration;
  _StrobeAction(this.isOn, this.duration);
}
