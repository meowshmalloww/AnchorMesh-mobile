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

  List<Widget> get _pages => [
    HomePage(onTabChange: _onItemTapped),
    const MapPage(),
    const OfflineUtilityPage(),
    const SOSPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.resq;

    return Scaffold(
      backgroundColor: colors.surface,
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: ResQNavBar(
        selectedIndex: _selectedIndex,
        onItemSelected: _onItemTapped,
      ),
    );
  }
}
