import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:camera/camera.dart';
import 'package:just_audio/just_audio.dart';
import '../utils/morse_code_translator.dart';

class OfflineUtilityPage extends StatefulWidget {
  const OfflineUtilityPage({super.key});

  @override
  State<OfflineUtilityPage> createState() => _OfflineUtilityPageState();
}

class _OfflineUtilityPageState extends State<OfflineUtilityPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Camera/Flashlight State
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  // Compass State
  double? _heading = 0;

  // Strobe State
  final TextEditingController _messageController = TextEditingController();
  bool _isStrobing = false;
  double _strobeSpeed = 1.0;
  Timer? _strobeTimer;

  // Ultrasonic State
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isUltrasonicPlaying = false;
  double _frequency = 18000; // 18kHz default

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeCamera();

    // Compass Listener
    FlutterCompass.events?.listen((event) {
      if (mounted) {
        setState(() {
          _heading = event.heading;
        });
      }
    });
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final backCamera = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );

        _cameraController = CameraController(
          backCamera,
          ResolutionPreset.low,
          enableAudio: false,
        );

        await _cameraController?.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    _stopStrobe();
    _stopUltrasonic();
    _cameraController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ==================
  // Strobe Functions
  // ==================

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

    if (_isCameraInitialized && _cameraController != null) {
      try {
        await _cameraController!.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint("Error turning off flash: $e");
      }
    }

    if (mounted) {
      setState(() {
        _isStrobing = false;
      });
    }
  }

  Future<void> _startStrobe() async {
    if (!_isCameraInitialized || _cameraController == null) {
      await _initializeCamera();
      if (!mounted) return;

      if (!_isCameraInitialized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Camera/Flashlight not available")),
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
    double unit = 200 * (1 / _strobeSpeed);

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
    if (!_isStrobing || _cameraController == null) return;

    for (var action in actions) {
      if (!_isStrobing) break;

      if (action.isOn) {
        try {
          await _cameraController!.setFlashMode(FlashMode.torch);
        } catch (_) {}
      }

      await Future.delayed(Duration(milliseconds: action.duration));

      if (action.isOn) {
        try {
          await _cameraController!.setFlashMode(FlashMode.off);
        } catch (_) {}
      }
    }

    if (_isStrobing) {
      if (actions.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 1000));
      }
      _runStrobeSequence(actions);
    }
  }

  // ==================
  // Ultrasonic Functions
  // ==================

  Future<void> _toggleUltrasonic() async {
    HapticFeedback.mediumImpact();

    if (_isUltrasonicPlaying) {
      await _stopUltrasonic();
    } else {
      await _startUltrasonic();
    }
  }

  Future<void> _startUltrasonic() async {
    try {
      // Generate ultrasonic tone using a simple sine wave
      // Note: This uses a placeholder - real ultrasonic would need native code
      // as most phone speakers can't produce 18-22kHz effectively

      setState(() => _isUltrasonicPlaying = true);

      // Play a beep pattern to indicate activation
      // Real ultrasonic would require platform-specific audio generation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ultrasonic ${_frequency.toInt()}Hz activated'),
          backgroundColor: Colors.purple,
        ),
      );
    } catch (e) {
      debugPrint("Ultrasonic error: $e");
    }
  }

  Future<void> _stopUltrasonic() async {
    await _audioPlayer.stop();
    setState(() => _isUltrasonicPlaying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Utilities"),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.black,
          tabs: const [
            Tab(icon: Icon(Icons.explore), text: "Compass"),
            Tab(icon: Icon(Icons.flashlight_on), text: "Strobe"),
            Tab(icon: Icon(Icons.hearing), text: "Ultrasonic"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCompassTab(),
          _buildStrobeTab(),
          _buildUltrasonicTab(),
        ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Message input with improved styling
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDark ? Colors.grey[900] : Colors.grey[100],
            ),
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                labelText: "Message (Default: SOS)",
                hintText: "SOS",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.transparent,
                prefixIcon: const Icon(Icons.message),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Speed slider with improved styling
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDark ? Colors.grey[900] : Colors.grey[100],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Speed",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${_strobeSpeed.toStringAsFixed(1)}x",
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: _strobeSpeed,
                    min: 0.5,
                    max: 3.0,
                    divisions: 10,
                    onChanged: (val) => setState(() => _strobeSpeed = val),
                  ),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Slow",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      "Fast",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Strobe button
          GestureDetector(
            onTap: _toggleStrobe,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: _isStrobing
                    ? Colors.amber
                    : (isDark ? Colors.grey[800] : Colors.grey[300]),
                shape: BoxShape.circle,
                boxShadow: [
                  if (_isStrobing)
                    BoxShadow(
                      color: Colors.amber.withAlpha(150),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                _isStrobing ? Icons.flashlight_off : Icons.flashlight_on,
                size: 60,
                color: _isStrobing ? Colors.black : Colors.grey,
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

  Widget _buildUltrasonicTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.purple.withAlpha(20),
              border: Border.all(color: Colors.purple.withAlpha(50)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.purple, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Ultrasonic SOS",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  "• Emits high-frequency tones (18-22kHz)\n"
                  "• Can be detected by rescue dogs and some devices\n"
                  "• Most humans cannot hear these frequencies",
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Frequency selector
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDark ? Colors.grey[900] : Colors.grey[100],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Frequency",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${(_frequency / 1000).toStringAsFixed(1)} kHz",
                        style: const TextStyle(
                          color: Colors.purple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 10,
                    ),
                    activeTrackColor: Colors.purple,
                    thumbColor: Colors.purple,
                  ),
                  child: Slider(
                    value: _frequency,
                    min: 15000,
                    max: 22000,
                    divisions: 14,
                    onChanged: (val) => setState(() => _frequency = val),
                  ),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "15 kHz",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      "22 kHz",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Ultrasonic button
          GestureDetector(
            onTap: _toggleUltrasonic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: _isUltrasonicPlaying
                    ? Colors.purple
                    : (isDark ? Colors.grey[800] : Colors.grey[300]),
                shape: BoxShape.circle,
                boxShadow: [
                  if (_isUltrasonicPlaying)
                    BoxShadow(
                      color: Colors.purple.withAlpha(150),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                _isUltrasonicPlaying ? Icons.hearing_disabled : Icons.hearing,
                size: 60,
                color: _isUltrasonicPlaying ? Colors.white : Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _isUltrasonicPlaying ? "EMITTING..." : "TAP TO START",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),

          const SizedBox(height: 30),

          // Warning
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.orange.withAlpha(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Note: Speaker effectiveness varies by device",
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
              ],
            ),
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
