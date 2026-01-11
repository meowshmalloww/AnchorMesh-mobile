import 'package:flutter/material.dart';
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
      extendBody: true,
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
