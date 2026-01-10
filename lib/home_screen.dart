import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'widgets/resq_nav_bar.dart';
import 'theme/resq_theme.dart';
import 'pages/home_page.dart';
import 'pages/map_page.dart';
import 'pages/offline_utility_page.dart';
import 'pages/sos_page.dart';
import 'pages/settings_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Request Bluetooth permissions
    if (Platform.isAndroid) {
      // Android 12+ requires these specific Bluetooth permissions
      await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    } else if (Platform.isIOS) {
      // iOS uses a single Bluetooth permission
      await Permission.bluetooth.request();
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.resq;

    return Scaffold(
      backgroundColor: colors.surface,
      // Use direct page reference instead of IndexedStack for better performance
      // IndexedStack keeps ALL pages alive in memory - wasteful for large pages
      body: _buildPage(_selectedIndex),
      bottomNavigationBar: ResQNavBar(
        selectedIndex: _selectedIndex,
        onItemSelected: _onItemTapped,
      ),
    );
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return HomePage(onTabChange: _onItemTapped);
      case 1:
        return const MapPage();
      case 2:
        return const OfflineUtilityPage();
      case 3:
        return const SOSPage();
      case 4:
        return const SettingsPage();
      default:
        return HomePage(onTabChange: _onItemTapped);
    }
  }
}
