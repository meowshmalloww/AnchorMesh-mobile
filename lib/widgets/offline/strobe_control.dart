import 'dart:async';
import 'package:flutter/material.dart';
import 'package:torch_light/torch_light.dart';
import '../../utils/morse_code_translator.dart';

class StrobeControl extends StatefulWidget {
  const StrobeControl({super.key});

  @override
  State<StrobeControl> createState() => _StrobeControlState();
}

class _StrobeAction {
  final bool isOn;
  final int duration;
  _StrobeAction(this.isOn, this.duration);
}

class _StrobeControlState extends State<StrobeControl> {
  final TextEditingController _messageController = TextEditingController(
    text: "SOS",
  );
  bool _isStrobing = false;
  double _strobeSpeed = 1.0;

  @override
  void dispose() {
    _isStrobing = false; // Stop loop
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _toggleStrobe() async {
    if (_isStrobing) {
      setState(() => _isStrobing = false);
      try {
        await TorchLight.disableTorch();
      } catch (_) {}
    } else {
      setState(() => _isStrobing = true);
      _startStrobe();
    }
  }

  Future<void> _startStrobe() async {
    final message = _messageController.text.trim().toUpperCase();
    if (message.isEmpty) return;

    final morse = MorseCodeTranslator.textToMorse(message);
    final unit = (200 / _strobeSpeed).round(); // Base unit in ms

    List<_StrobeAction> actions = [];

    for (var char in morse.split('')) {
      if (char == '.') {
        actions.add(_StrobeAction(true, unit));
        actions.add(_StrobeAction(false, unit));
      } else if (char == '-') {
        actions.add(_StrobeAction(true, unit * 3));
        actions.add(_StrobeAction(false, unit));
      } else if (char == ' ') {
        actions.add(_StrobeAction(false, unit * 3));
      } else if (char == '/') {
        actions.add(_StrobeAction(false, unit * 7));
      }
    }
    // Add pause at end
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Message input
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

          // Speed slider
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
}
