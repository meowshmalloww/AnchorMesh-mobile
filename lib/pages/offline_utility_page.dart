// ignore_for_file: subtype_of_sealed_class, deprecated_member_use, experimental_member_use
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../widgets/offline/strobe_control.dart';
import '../widgets/offline/ultrasonic_control.dart';
import 'signal_locator_page.dart';
import 'compass_pointer_page.dart';

class OfflineUtilityPage extends StatefulWidget {
  const OfflineUtilityPage({super.key});

  @override
  State<OfflineUtilityPage> createState() => _OfflineUtilityPageState();
}

class _OfflineUtilityPageState extends State<OfflineUtilityPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  double? _heading = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _initCompass();
  }

  void _initCompass() {
    FlutterCompass.events?.listen((event) {
      if (mounted) {
        setState(() {
          _heading = event.heading;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Utilities"),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable:
              true, // Re-enable scrollable for 5 tabs on small screens
          labelColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.black,
          tabs: const [
            Tab(icon: Icon(Icons.explore), text: "Compass"),
            Tab(icon: Icon(Icons.navigation), text: "Pointer"),
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
          const CompassPointerPage(),
          const StrobeControl(),
          const UltrasonicControl(),
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
}
