// ignore_for_file: subtype_of_sealed_class, deprecated_member_use, experimental_member_use
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:compassx/compassx.dart';

import '../widgets/offline/strobe_control.dart';
import '../widgets/offline/ultrasonic_control.dart';
import '../theme/resq_theme.dart';
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
    CompassX.events.listen((event) {
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
    final colors = context.resq;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Column(
        children: [
          // Minimal frosted tab bar
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: EdgeInsets.only(top: topPadding),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated.withAlpha(isDark ? 115 : 140),
                  border: Border(
                    bottom: BorderSide(
                      color: colors.meshLine.withAlpha(76),
                      width: 0.5,
                    ),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  labelColor: colors.textPrimary,
                  unselectedLabelColor: colors.textSecondary,
                  indicatorColor: colors.accentSecondary,
                  tabs: const [
                    Tab(icon: Icon(Icons.explore, size: 20), text: "Compass"),
                    Tab(icon: Icon(Icons.navigation, size: 20), text: "Pointer"),
                    Tab(icon: Icon(Icons.flashlight_on, size: 20), text: "Strobe"),
                    Tab(icon: Icon(Icons.hearing, size: 20), text: "Audio"),
                    Tab(icon: Icon(Icons.radar, size: 20), text: "Scan"),
                  ],
                ),
              ),
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCompassTab(),
                const CompassPointerPage(),
                const StrobeControl(),
                const UltrasonicControl(),
                const SignalLocatorPage(),
              ],
            ),
          ),
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
