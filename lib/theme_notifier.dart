import 'package:flutter/material.dart';

class ThemeNotifier extends ValueNotifier<ThemeMode> {
  // Singleton instance
  static final ThemeNotifier _instance = ThemeNotifier._internal();

  factory ThemeNotifier() {
    return _instance;
  }

  ThemeNotifier._internal() : super(ThemeMode.light);

  void toggleTheme() {
    value = value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  }

  void setTheme(ThemeMode mode) {
    value = mode;
  }
}
