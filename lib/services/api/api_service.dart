/// API Service
/// Handles HTTP and WebSocket communication with the backend server

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../models/sos_alert.dart';
import '../../models/device_info.dart';

/// Retry configuration
class RetryConfig {
  final int maxRetries;
  final Duration initialDelay;
  final double backoffMultiplier;
  final Duration maxDelay;

  const RetryConfig({
    this.maxRetries = 5,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(minutes: 5),
  });

  /// Calculate delay for a given attempt (0-indexed)
  Duration getDelay(int attempt) {
    final delay = initialDelay.inMilliseconds *
        pow(backoffMultiplier, attempt);
    return Duration(
      milliseconds: min(delay.toInt(), maxDelay.inMilliseconds),
    );
  }
}

/// API configuration
class ApiConfig {
  final String baseUrl;
  final String wsUrl;
  final Duration timeout;
  final RetryConfig retryConfig;

  ApiConfig({
    required this.baseUrl,
    String? wsUrl,
    this.timeout = const Duration(seconds: 30),
    this.retryConfig = const RetryConfig(),
  }) : wsUrl = wsUrl ?? baseUrl.replaceFirst('http', 'ws');
}

/// API response wrapper
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final int statusCode;

  const ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.statusCode = 200,
  });

  factory ApiResponse.success(T data, {int statusCode = 200}) {
    return ApiResponse(success: true, data: data, statusCode: statusCode);
  }

  factory ApiResponse.error(String error, {int statusCode = 500}) {
    return ApiResponse(success: false, error: error, statusCode: statusCode);
  }
}

/// Server events for real-time updates
abstract class ServerEvent {}

class SosAcknowledgedEvent extends ServerEvent {
  final String messageId;
  final String status;
  SosAcknowledgedEvent(this.messageId, this.status);
}

class SosStatusUpdateEvent extends ServerEvent {
  final String messageId;
  final String status;
  SosStatusUpdateEvent(this.messageId, this.status);
}

class ConnectionStatusEvent extends ServerEvent {
  final bool connected;
  ConnectionStatusEvent(this.connected);
}

/// API Service for server communication
class ApiService {
  final ApiConfig config;
  final LocalDevice localDevice;

  String? _authToken;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  bool _isWsConnected = false;
  final _serverEventsController = StreamController<ServerEvent>.broadcast();

  /// Pending messages queue (for offline support)
  final List<Map<String, dynamic>> _pendingMessages = [];

  ApiService({
    required this.config,
    required this.localDevice,
  });

  /// Server events stream
  Stream<ServerEvent> get serverEvents => _serverEventsController.stream;

  /// Whether WebSocket is connected
  bool get isWsConnected => _isWsConnected;

  /// Set authentication token
  void setAuthToken(String token) {
    _authToken = token;
  }

  /// Get HTTP headers
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
        'X-Device-ID': localDevice.deviceId,
      };

  /// Register device with server
  Future<ApiResponse<DeviceRegistrationResponse>> registerDevice() async {
    try {
      final response = await http
          .post(
            Uri.parse('${config.baseUrl}/api/v1/device/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(localDevice.toJson()),
          )
          .timeout(config.timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final registration = DeviceRegistrationResponse.fromJson(json);

        _authToken = registration.token;
        localDevice.authToken = registration.token;
        localDevice.appSignature = registration.appSignature;

        return ApiResponse.success(registration, statusCode: response.statusCode);
      } else {
        return ApiResponse.error(
          'Registration failed: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Send SOS alert directly to server with retry logic
  Future<ApiResponse<Map<String, dynamic>>> sendSosAlert(SOSAlert alert, {bool retry = true}) async {
    return _sendWithRetry(
      () => _sendSosAlertOnce(alert),
      retry: retry,
      onFinalFailure: () => _queueMessage('sos_alert', alert.toJson()),
    );
  }

  /// Single attempt to send SOS alert
  Future<ApiResponse<Map<String, dynamic>>> _sendSosAlertOnce(SOSAlert alert) async {
    final response = await http
        .post(
          Uri.parse('${config.baseUrl}/api/v1/sos/alert'),
          headers: _headers,
          body: jsonEncode(alert.toJson()),
        )
        .timeout(config.timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResponse.success(json, statusCode: response.statusCode);
    } else {
      return ApiResponse.error(
        'Failed to send SOS: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  /// Generic retry wrapper with exponential backoff
  Future<ApiResponse<T>> _sendWithRetry<T>(
    Future<ApiResponse<T>> Function() operation, {
    bool retry = true,
    void Function()? onFinalFailure,
  }) async {
    final retryConfig = config.retryConfig;
    int attempt = 0;

    while (true) {
      try {
        final response = await operation();

        if (response.success) {
          return response;
        }

        // Don't retry client errors (4xx)
        if (response.statusCode >= 400 && response.statusCode < 500) {
          return response;
        }

        // Check if we should retry
        if (!retry || attempt >= retryConfig.maxRetries) {
          onFinalFailure?.call();
          return response;
        }

        // Wait before retrying
        final delay = retryConfig.getDelay(attempt);
        await Future.delayed(delay);
        attempt++;
      } catch (e) {
        if (!retry || attempt >= retryConfig.maxRetries) {
          onFinalFailure?.call();
          return ApiResponse.error('Network error after $attempt retries: $e');
        }

        // Wait before retrying
        final delay = retryConfig.getDelay(attempt);
        await Future.delayed(delay);
        attempt++;
      }
    }
  }

  /// Send relayed SOS alert to server
  Future<ApiResponse<Map<String, dynamic>>> sendRelayedSos(SOSAlert alert) async {
    try {
      final payload = alert.toJson();
      payload['relayedBy'] = localDevice.deviceId;

      final response = await http
          .post(
            Uri.parse('${config.baseUrl}/api/v1/sos/relay'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(config.timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(json, statusCode: response.statusCode);
      } else {
        return ApiResponse.error(
          'Failed to relay SOS: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      // Queue for later
      final payload = alert.toJson();
      payload['relayedBy'] = localDevice.deviceId;
      _queueMessage('sos_relay', payload);
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Cancel SOS alert
  Future<ApiResponse<void>> cancelSos(String messageId) async {
    try {
      final response = await http
          .post(
            Uri.parse('${config.baseUrl}/api/v1/sos/$messageId/cancel'),
            headers: _headers,
          )
          .timeout(config.timeout);

      if (response.statusCode == 200) {
        return ApiResponse.success(null);
      } else {
        return ApiResponse.error('Failed to cancel SOS: ${response.statusCode}');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Update device location
  Future<ApiResponse<void>> updateLocation(GeoLocation location) async {
    try {
      final response = await http
          .put(
            Uri.parse('${config.baseUrl}/api/v1/device/location'),
            headers: _headers,
            body: jsonEncode(location.toJson()),
          )
          .timeout(config.timeout);

      return response.statusCode == 200
          ? ApiResponse.success(null)
          : ApiResponse.error('Failed to update location');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Send heartbeat to server
  Future<ApiResponse<void>> heartbeat() async {
    try {
      final response = await http
          .post(
            Uri.parse('${config.baseUrl}/api/v1/device/heartbeat'),
            headers: _headers,
            body: jsonEncode({
              if (localDevice.lastKnownLocation != null)
                'location': localDevice.lastKnownLocation!.toJson(),
              'hasInternet': true,
            }),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200
          ? ApiResponse.success(null)
          : ApiResponse.error('Heartbeat failed');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  /// Connect WebSocket for real-time updates
  Future<void> connectWebSocket() async {
    if (_isWsConnected) return;

    try {
      _wsChannel = WebSocketChannel.connect(
        Uri.parse('${config.wsUrl}/ws'),
      );

      _wsSubscription = _wsChannel!.stream.listen(
        _handleWsMessage,
        onError: _handleWsError,
        onDone: _handleWsDisconnect,
      );

      // Authenticate
      _wsChannel!.sink.add(jsonEncode({
        'type': 'auth',
        'token': _authToken,
      }));

      _isWsConnected = true;
      _serverEventsController.add(ConnectionStatusEvent(true));

      // Start heartbeat
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _sendWsHeartbeat(),
      );
    } catch (e) {
      _scheduleReconnect();
    }
  }

  /// Handle WebSocket message
  void _handleWsMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'sos_acknowledged':
          _serverEventsController.add(SosAcknowledgedEvent(
            data['messageId'] as String,
            data['status'] as String,
          ));
          break;
        case 'sos_update':
          _serverEventsController.add(SosStatusUpdateEvent(
            data['alert']['messageId'] as String,
            data['updateType'] as String,
          ));
          break;
        case 'auth_success':
          _isWsConnected = true;
          break;
        case 'auth_failed':
          _isWsConnected = false;
          break;
      }
    } catch (e) {
      // Ignore malformed messages
    }
  }

  /// Handle WebSocket error
  void _handleWsError(dynamic error) {
    _isWsConnected = false;
    _serverEventsController.add(ConnectionStatusEvent(false));
    _scheduleReconnect();
  }

  /// Handle WebSocket disconnect
  void _handleWsDisconnect() {
    _isWsConnected = false;
    _serverEventsController.add(ConnectionStatusEvent(false));
    _scheduleReconnect();
  }

  /// Send WebSocket heartbeat
  void _sendWsHeartbeat() {
    if (_wsChannel != null && _isWsConnected) {
      _wsChannel!.sink.add(jsonEncode({
        'type': 'heartbeat',
        'timestamp': DateTime.now().toIso8601String(),
      }));
    }
  }

  /// Schedule WebSocket reconnection
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      connectWebSocket();
    });
  }

  /// Queue message for later sending
  void _queueMessage(String type, Map<String, dynamic> payload) {
    _pendingMessages.add({
      'type': type,
      'payload': payload,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Flush pending messages
  Future<void> flushPendingMessages() async {
    final messages = List.from(_pendingMessages);
    _pendingMessages.clear();

    for (final msg in messages) {
      final type = msg['type'] as String;
      final payload = msg['payload'] as Map<String, dynamic>;

      try {
        if (type == 'sos_alert') {
          await http.post(
            Uri.parse('${config.baseUrl}/api/v1/sos/alert'),
            headers: _headers,
            body: jsonEncode(payload),
          );
        } else if (type == 'sos_relay') {
          await http.post(
            Uri.parse('${config.baseUrl}/api/v1/sos/relay'),
            headers: _headers,
            body: jsonEncode(payload),
          );
        }
      } catch (e) {
        // Re-queue if still failing
        _pendingMessages.add(msg as Map<String, dynamic>);
      }
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    await _wsSubscription?.cancel();
    await _wsChannel?.sink.close();
    await _serverEventsController.close();
  }
}
