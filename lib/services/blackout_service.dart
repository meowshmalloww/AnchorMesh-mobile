import 'package:flutter/foundation.dart';
import 'package:screen_brightness/screen_brightness.dart';

class BlackoutService {
  static final BlackoutService instance = BlackoutService._internal();

  final ValueNotifier<bool> enabled = ValueNotifier(false);
  double? _originalBrightness;

  BlackoutService._internal();

  /// Enable Blackout Mode
  /// - Sets brightness to minimum (0.0 or 0.01)
  /// - Notifies UI to show black overlay
  Future<void> enable() async {
    try {
      // Get current brightness
      _originalBrightness = await ScreenBrightness().application;
      await ScreenBrightness().setApplicationScreenBrightness(0.0);
      enabled.value = true;
    } catch (e) {
      debugPrint("Blackout Error: $e");
    }
  }

  /// Disable Blackout Mode
  /// - Restores brightness
  /// - Removes UI overlay
  Future<void> disable() async {
    try {
      if (_originalBrightness != null) {
        await ScreenBrightness().setApplicationScreenBrightness(
          _originalBrightness!,
        );
      } else {
        await ScreenBrightness().resetApplicationScreenBrightness();
      }
    } catch (e) {
      debugPrint("Failed to disable blackout: $e");
    } finally {
      enabled.value = false;
    }
  }

  void toggle() async {
    if (enabled.value) {
      await disable();
    } else {
      await enable();
    }
  }
}
