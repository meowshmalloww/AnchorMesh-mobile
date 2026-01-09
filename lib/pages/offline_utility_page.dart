// ignore_for_file: subtype_of_sealed_class, deprecated_member_use, experimental_member_use
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:torch_light/torch_light.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import '../utils/morse_code_translator.dart';
import '../utils/fft_analyzer.dart';
import '../widgets/adaptive/adaptive_widgets.dart';
import 'signal_locator_page.dart';

class OfflineUtilityPage extends StatefulWidget {
  const OfflineUtilityPage({super.key});

  @override
  State<OfflineUtilityPage> createState() => _OfflineUtilityPageState();
}

class _OfflineUtilityPageState extends State<OfflineUtilityPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Compass State
  double? _heading = 0;
  StreamSubscription<CompassEvent>? _compassSubscription;

  // Strobe State
  final TextEditingController _messageController = TextEditingController();
  bool _isStrobing = false;
  double _strobeSpeed = 1.0;
  Timer? _strobeTimer;

  // Ultrasonic State
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isUltrasonicPlaying = false;
  bool _isDetecting = false;
  double _frequency = 18000; // 18kHz default
  double _detectedLevel = 0.0;
  Timer? _detectorTimer;
  bool _micPermissionGranted = false;

  // Audio capture for detector
  final FlutterAudioCapture _audioCapture = FlutterAudioCapture();
  final FFTAnalyzer _fftAnalyzer = FFTAnalyzer(sampleRate: 44100, fftSize: 4096);
  final List<double> _audioBuffer = [];
  double? _detectedFrequency;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // Compass Listener
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (mounted) {
        setState(() {
          _heading = event.heading;
        });
      }
    });

    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final micStatus = await Permission.microphone.status;
    setState(() => _micPermissionGranted = micStatus.isGranted);
  }

  Future<bool> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    setState(() => _micPermissionGranted = status.isGranted);
    return status.isGranted;
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _tabController.dispose();
    _messageController.dispose();
    _stopStrobe();
    _stopUltrasonic();
    _detectorTimer?.cancel();
    _audioCapture.stop().catchError((_) {});
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

  Future<void> _stopStrobe() async {
    _strobeTimer?.cancel();
    _strobeTimer = null;

    try {
      await TorchLight.disableTorch();
    } catch (e) {
      debugPrint("Error turning off flash: $e");
    }

    if (mounted) {
      setState(() {
        _isStrobing = false;
      });
    }
  }

  Future<void> _startStrobe() async {
    try {
      // Check if torch is available
    } catch (e) {
      showWarningSnackBar(context, 'Flashlight not available');
      return;
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
      // Generate sine wave audio data
      final sampleRate = 44100;
      final duration = 5; // 5 seconds
      final numSamples = sampleRate * duration;
      final bytes = BytesBuilder();

      // WAV header
      bytes.add(_buildWavHeader(numSamples, sampleRate));

      // Generate sine wave at selected frequency
      for (int i = 0; i < numSamples; i++) {
        final sample =
            (math.sin(2 * math.pi * _frequency * i / sampleRate) * 32767)
                .toInt();
        bytes.addByte(sample & 0xFF);
        bytes.addByte((sample >> 8) & 0xFF);
      }

      final audioBytes = bytes.toBytes();

      // Create audio source from bytes
      await _audioPlayer.setAudioSource(_ByteAudioSource(audioBytes));
      await _audioPlayer.setLoopMode(LoopMode.one);
      await _audioPlayer.play();

      setState(() => _isUltrasonicPlaying = true);

      if (mounted) {
        showInfoSnackBar(context, 'Emitting ${(_frequency / 1000).toStringAsFixed(1)} kHz');
      }
    } catch (e) {
      debugPrint("Ultrasonic error: $e");
      if (mounted) {
        showErrorSnackBar(context, 'Error: $e');
      }
    }
  }

  Uint8List _buildWavHeader(int numSamples, int sampleRate) {
    final byteRate = sampleRate * 2; // 16-bit mono
    final blockAlign = 2;
    final dataSize = numSamples * 2;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);

    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // space
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, 16, Endian.little); // bits per sample

    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    return header.buffer.asUint8List();
  }

  Future<void> _stopUltrasonic() async {
    await _audioPlayer.stop();
    setState(() => _isUltrasonicPlaying = false);
  }

  // ==================
  // Detector Functions
  // ==================

  Future<void> _toggleDetector() async {
    HapticFeedback.mediumImpact();

    if (_isDetecting) {
      await _stopDetector();
    } else {
      await _startDetector();
    }
  }

  Future<void> _startDetector() async {
    // Request microphone permission
    if (!_micPermissionGranted) {
      final granted = await _requestMicrophonePermission();
      if (!granted) {
        if (mounted) {
          showErrorSnackBar(context, 'Microphone permission required for detector');
        }
        return;
      }
    }

    setState(() => _isDetecting = true);
    _audioBuffer.clear();

    try {
      // Start audio capture with callback for real-time processing
      await _audioCapture.start(
        (dynamic obj) {
          if (!_isDetecting) return;

          // Convert incoming audio data to double samples
          if (obj is Float64List) {
            _audioBuffer.addAll(obj);
          } else if (obj is List) {
            for (var sample in obj) {
              if (sample is double) {
                _audioBuffer.add(sample);
              } else if (sample is num) {
                _audioBuffer.add(sample.toDouble());
              }
            }
          }

          // Keep buffer at reasonable size (keep last 8192 samples)
          while (_audioBuffer.length > 8192) {
            _audioBuffer.removeAt(0);
          }
        },
        (error) {
          debugPrint('Audio capture error: $error');
        },
        sampleRate: 44100,
        bufferSize: 4096,
      );

      // Start periodic FFT analysis
      _detectorTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!_isDetecting) {
          timer.cancel();
          return;
        }

        if (_audioBuffer.length >= 4096) {
          // Analyze ultrasonic level using FFT
          final level = _fftAnalyzer.analyzeUltrasonicLevel(_audioBuffer);
          final freq = _fftAnalyzer.getDominantUltrasonicFrequency(_audioBuffer);

          if (mounted) {
            setState(() {
              _detectedLevel = level;
              _detectedFrequency = freq;
            });

            // Vibrate on strong signal detection
            if (level > 0.5) {
              HapticFeedback.lightImpact();
            }
          }
        }
      });

      if (mounted) {
        showInfoSnackBar(context, 'Listening for ultrasonic signals...');
      }
    } catch (e) {
      debugPrint('Failed to start audio capture: $e');
      if (mounted) {
        showErrorSnackBar(context, 'Failed to start detector: $e');
        setState(() => _isDetecting = false);
      }
    }
  }

  Future<void> _stopDetector() async {
    _detectorTimer?.cancel();
    _detectorTimer = null;

    try {
      await _audioCapture.stop();
    } catch (e) {
      debugPrint('Error stopping audio capture: $e');
    }

    _audioBuffer.clear();

    if (mounted) {
      setState(() {
        _isDetecting = false;
        _detectedLevel = 0.0;
        _detectedFrequency = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Utilities"),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.black,
          tabs: const [
            Tab(icon: Icon(Icons.explore), text: "Compass"),
            Tab(icon: Icon(Icons.flashlight_on), text: "Strobe"),
            Tab(icon: Icon(Icons.hearing), text: "Ultrasonic"),
            Tab(icon: Icon(Icons.radar), text: "Locator"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCompassTab(),
          _buildStrobeTab(),
          _buildUltrasonicTab(),
          const SignalLocatorPage(),
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
          // Mode selector (Emitter / Detector)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDark ? Colors.grey[900] : Colors.grey[200],
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {}),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !_isDetecting && !_isUltrasonicPlaying
                            ? Colors.purple
                            : (_isUltrasonicPlaying
                                  ? Colors.purple
                                  : Colors.transparent),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.speaker,
                            size: 18,
                            color:
                                _isUltrasonicPlaying ||
                                    (!_isDetecting && !_isUltrasonicPlaying)
                                ? Colors.white
                                : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Emitter",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color:
                                  _isUltrasonicPlaying ||
                                      (!_isDetecting && !_isUltrasonicPlaying)
                                  ? Colors.white
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {}),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _isDetecting ? Colors.teal : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mic,
                            size: 18,
                            color: _isDetecting ? Colors.white : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Detector",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _isDetecting ? Colors.white : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

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
                  "• Emitter: Sends high-frequency tones (15-22kHz)\n"
                  "• Detector: Listens for ultrasonic signals from other devices\n"
                  "• Works on both iOS and Android",
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Frequency selector (for emitter)
          if (!_isDetecting)
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
                      onChanged: _isUltrasonicPlaying
                          ? null
                          : (val) => setState(() => _frequency = val),
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

          // Detector level indicator
          if (_isDetecting)
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
                      const Row(
                        children: [
                          Icon(Icons.graphic_eq, color: Colors.teal),
                          SizedBox(width: 8),
                          Text(
                            "Signal Level",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      if (_detectedFrequency != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "${(_detectedFrequency! / 1000).toStringAsFixed(1)} kHz",
                            style: const TextStyle(
                              color: Colors.teal,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _detectedLevel,
                      minHeight: 20,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _detectedLevel > 0.7
                            ? Colors.green
                            : _detectedLevel > 0.3
                            ? Colors.orange
                            : Colors.teal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _detectedLevel > 0.7
                        ? "Strong ultrasonic signal detected!"
                        : _detectedLevel > 0.3
                        ? "Weak ultrasonic signal"
                        : "Listening for ultrasonic frequencies (15-22 kHz)...",
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 40),

          // Main buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Emitter button
              GestureDetector(
                onTap: _isDetecting ? null : _toggleUltrasonic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: _isUltrasonicPlaying
                        ? Colors.purple
                        : (_isDetecting
                              ? Colors.grey[400]
                              : (isDark ? Colors.grey[800] : Colors.grey[300])),
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.speaker,
                        size: 40,
                        color: _isUltrasonicPlaying
                            ? Colors.white
                            : Colors.grey,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "EMIT",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _isUltrasonicPlaying
                              ? Colors.white
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // Detector button
              GestureDetector(
                onTap: _isUltrasonicPlaying ? null : _toggleDetector,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: _isDetecting
                        ? Colors.teal
                        : (_isUltrasonicPlaying
                              ? Colors.grey[400]
                              : (isDark ? Colors.grey[800] : Colors.grey[300])),
                    shape: BoxShape.circle,
                    boxShadow: [
                      if (_isDetecting)
                        BoxShadow(
                          color: Colors.teal.withAlpha(150),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mic,
                        size: 40,
                        color: _isDetecting ? Colors.white : Colors.grey,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "DETECT",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _isDetecting ? Colors.white : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          Text(
            _isUltrasonicPlaying
                ? "EMITTING..."
                : _isDetecting
                ? "LISTENING..."
                : "TAP TO START",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),

          const SizedBox(height: 30),

          // Permission status
          if (!_micPermissionGranted)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.blue.withAlpha(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Microphone permission needed for detector",
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                  TextButton(
                    onPressed: _requestMicrophonePermission,
                    child: const Text("Grant"),
                  ),
                ],
              ),
            ),

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
                    "Note: Speaker/mic effectiveness varies by device",
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

/// Custom audio source for playing generated audio bytes
class _ByteAudioSource extends StreamAudioSource {
  final Uint8List _buffer;

  _ByteAudioSource(List<int> bytes) : _buffer = Uint8List.fromList(bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _buffer.length;
    return StreamAudioResponse(
      sourceLength: _buffer.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_buffer.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}
