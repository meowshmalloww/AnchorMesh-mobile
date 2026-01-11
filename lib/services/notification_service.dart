import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/sos_packet.dart';
import '../models/sos_status.dart';

/// Service to handle notifications and navigation for SOS alerts
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // Callback for when user should navigate to map with specific coordinates
  void Function(double lat, double lon, int userId)? onNavigateToEmergency;

  // Callback for showing in-app alert
  void Function(SOSPacket packet)? onShowInAppAlert;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      final settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final initResult = await _notifications.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
        onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTapped,
      );

      debugPrint('Notification plugin initialized: $initResult');

      // Create high priority channel for Android
      const androidChannel = AndroidNotificationChannel(
        'sos_emergency',
        'SOS Emergency Alerts',
        description: 'Critical alerts for nearby SOS signals',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      _initialized = true;
    } catch (e) {
      debugPrint('Failed to initialize notification service: $e');
      // Mark as initialized to prevent repeated attempts
      _initialized = true;
      rethrow;
    }
  }

  /// Handle notification tap when app is in foreground/background
  void _onNotificationTapped(NotificationResponse response) {
    _handleNotificationPayload(response.payload);
  }

  /// Handle notification tap when app was terminated
  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTapped(NotificationResponse response) {
    // This runs in isolate - we'll handle it when app opens
    // Store the payload for later processing
    _pendingPayload = response.payload;
  }

  static String? _pendingPayload;

  /// Check and handle any pending notification payload (from terminated state)
  void checkPendingNotification() {
    if (_pendingPayload != null) {
      _handleNotificationPayload(_pendingPayload);
      _pendingPayload = null;
    }
  }

  void _handleNotificationPayload(String? payload) {
    if (payload == null) return;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final lat = data['lat'] as double?;
      final lon = data['lon'] as double?;
      final userId = data['userId'] as int?;

      if (lat != null && lon != null && userId != null) {
        onNavigateToEmergency?.call(lat, lon, userId);
      }
    } catch (e) {
      debugPrint('Failed to parse notification payload: $e');
    }
  }

  /// Show a local notification for received SOS
  Future<void> showSOSNotification(SOSPacket packet) async {
    // Don't notify for safe status
    if (packet.status == SOSStatus.safe) return;

    final payload = jsonEncode({
      'lat': packet.latitude,
      'lon': packet.longitude,
      'userId': packet.userId,
      'status': packet.status.index,
    });

    final androidDetails = AndroidNotificationDetails(
      'sos_emergency',
      'SOS Emergency Alerts',
      channelDescription: 'Critical alerts for nearby SOS signals',
      importance: Importance.max,
      priority: Priority.high,
      color: Color(packet.status.colorValue),
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      ticker: 'Emergency SOS Alert',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      packet.userId, // Use userId as notification ID to prevent duplicates
      '${packet.status.emoji} ${packet.status.label}',
      'Someone nearby needs help! Tap to view location.',
      details,
      payload: payload,
    );

    // Also trigger in-app alert
    onShowInAppAlert?.call(packet);
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}
