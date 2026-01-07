import 'package:flutter/material.dart';
import '../theme_notifier.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = ThemeNotifier();
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        // Colors handled by Theme in main.dart now
        elevation: 0,
      ),
      body: ListView(
        children: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, themeMode, child) {
              return SwitchListTile(
                title: const Text("Dark Mode"),
                value: isDarkMode,
                onChanged: (value) {
                  themeNotifier.toggleTheme();
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
