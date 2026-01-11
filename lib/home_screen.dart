import 'dart:async';
import 'package:flutter/material.dart';
import 'widgets/resq_nav_bar.dart';
import 'widgets/sos_notification_banner.dart';
import 'theme/resq_theme.dart';
import 'pages/home_page.dart';
import 'pages/map_page.dart';
import 'pages/offline_utility_page.dart';
import 'pages/sos_page.dart';
import 'pages/settings_page.dart';
import 'models/sos_packet.dart';
import 'models/sos_status.dart';
import 'services/ble_service.dart';
import 'services/notification_service.dart';

/// Global key to access HomeScreen state from anywhere
final GlobalKey<HomeScreenState> homeScreenKey = GlobalKey<HomeScreenState>();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final BLEService _bleService = BLEService.instance;
  StreamSubscription? _packetSubscription;

  // Pending navigation coordinates (set when notification is tapped)
  double? _pendingLat;
  double? _pendingLon;

  // Currently shown SOS alert overlay
  SOSPacket? _alertPacket;

  // Track recently shown alerts to prevent spam
  final Set<String> _recentlyShownAlerts = {};

  @override
  void initState() {
    super.initState();
    _setupNotificationHandlers();
    _setupPacketListener();
  }

  @override
  void dispose() {
    _packetSubscription?.cancel();
    super.dispose();
  }

  void _setupNotificationHandlers() {
    final notificationService = NotificationService.instance;

    // Handle navigation from notification tap
    notificationService.onNavigateToEmergency = (lat, lon, userId) {
      navigateToEmergency(lat, lon);
    };

    // Handle in-app alert display
    notificationService.onShowInAppAlert = (packet) {
      _showSOSAlert(packet);
    };

    // Check for pending notification from terminated state
    notificationService.checkPendingNotification();
  }

  void _setupPacketListener() {
    _packetSubscription?.cancel();
    _packetSubscription = _bleService.onPacketReceived.listen(
      (packet) {
        // Show notification and in-app alert for new SOS packets
        if (packet.status != SOSStatus.safe) {
          NotificationService.instance.showSOSNotification(packet);
        }
      },
      onError: (error) {
        debugPrint('Packet listener error: $error');
      },
      cancelOnError: false,
    );
  }

  /// Navigate to the map and center on emergency coordinates
  void navigateToEmergency(double lat, double lon) {
    setState(() {
      _pendingLat = lat;
      _pendingLon = lon;
      _selectedIndex = 1; // Map tab
    });
  }

  /// Get and clear pending coordinates (called by MapPage)
  ({double lat, double lon})? consumePendingCoordinates() {
    if (_pendingLat != null && _pendingLon != null) {
      final coords = (lat: _pendingLat!, lon: _pendingLon!);
      _pendingLat = null;
      _pendingLon = null;
      return coords;
    }
    return null;
  }

  void _showSOSAlert(SOSPacket packet) {
    // Prevent duplicate alerts for same packet
    final alertKey = '${packet.userId}-${packet.sequence}';
    if (_recentlyShownAlerts.contains(alertKey)) return;
    _recentlyShownAlerts.add(alertKey);

    // Clean up old alerts after 5 minutes
    Future.delayed(const Duration(minutes: 5), () {
      _recentlyShownAlerts.remove(alertKey);
    });

    // Don't show overlay if already showing one
    if (_alertPacket != null) return;

    setState(() {
      _alertPacket = packet;
    });
  }

  void _dismissAlert() {
    setState(() {
      _alertPacket = null;
    });
  }

  void _viewAlertOnMap() {
    if (_alertPacket != null) {
      navigateToEmergency(_alertPacket!.latitude, _alertPacket!.longitude);
    }
    _dismissAlert();
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
      extendBody: true,
      body: Stack(
        children: [
          // Main content
          _buildPage(_selectedIndex),

          // SOS Notification Banner (simple popup at top)
          if (_alertPacket != null)
            SOSNotificationBanner(
              packet: _alertPacket!,
              onDismiss: _dismissAlert,
              onViewOnMap: _viewAlertOnMap,
            ),
        ],
      ),
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
