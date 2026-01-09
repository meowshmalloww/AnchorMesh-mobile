import 'dart:async';
import 'dart:io' show Platform;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/api_config.dart';
import '../models/sos_packet.dart';
import 'packet_store.dart';
import 'connectivity_service.dart';

/// Sync status for UI feedback
enum SyncStatus { idle, syncing, completed, error }

/// Result of a sync operation
class SyncResult {
  final int synced;
  final int failed;
  final int duplicates;
  final bool offline;

  SyncResult({
    required this.synced,
    required this.failed,
    required this.duplicates,
    this.offline = false,
  });

  int get total => synced + failed + duplicates;

  @override
  String toString() =>
      'SyncResult(synced: $synced, failed: $failed, duplicates: $duplicates)';
}

/// Supabase sync service for cloud backup of SOS packets
///
/// Listens for connectivity changes and automatically syncs
/// unsynced packets when internet becomes available.
class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseClient? _client;

  SupabaseService._();

  static SupabaseService get instance {
    _instance ??= SupabaseService._();
    return _instance!;
  }

  // Services
  final PacketStore _packetStore = PacketStore.instance;
  final ConnectivityChecker _connectivity = ConnectivityChecker.instance;

  // State
  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _isInitialized = false;
  StreamSubscription<bool>? _connectivitySub;
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  final _lastSyncController = StreamController<DateTime?>.broadcast();

  /// Stream of sync status updates
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  /// Stream of last sync time updates
  Stream<DateTime?> get lastSyncStream => _lastSyncController.stream;

  /// Current sync status
  SyncStatus _currentStatus = SyncStatus.idle;
  SyncStatus get currentStatus => _currentStatus;

  /// Last successful sync time
  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Check if initialized
  bool get isInitialized => _isInitialized;

  /// Get Supabase client
  SupabaseClient get client {
    if (_client == null) {
      throw StateError(
        'SupabaseService not initialized. Call initialize() first.',
      );
    }
    return _client!;
  }

  /// Initialize Supabase client and start sync monitoring
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Supabase.initialize(
        url: ApiConfig.supabaseUrl,
        anonKey: ApiConfig.supabaseAnonKey,
      );
      _client = Supabase.instance.client;
      _isInitialized = true;

      // Register device on first launch
      await _registerDevice();

      // Listen for connectivity changes
      _connectivitySub = _connectivity.statusStream.listen((isOnline) {
        if (isOnline) {
          // Delay slightly to ensure connection is stable
          Future.delayed(const Duration(seconds: 2), () {
            syncPendingPackets();
          });
        }
      });

      // Start periodic sync
      _syncTimer = Timer.periodic(
        Duration(seconds: ApiConfig.syncIntervalSeconds),
        (_) {
          if (_connectivity.isOnline) {
            syncPendingPackets();
          }
        },
      );

      // Initial sync if online
      if (_connectivity.isOnline) {
        syncPendingPackets();
      }
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }
  }

  /// Register this device with Supabase
  Future<void> _registerDevice() async {
    try {
      final userId = await _packetStore.getUserId();
      final deviceId = userId.toRadixString(16).padLeft(8, '0');

      await client.from('devices').upsert(
        {
          'device_id': deviceId,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'is_active': true,
          'last_seen': DateTime.now().toUtc().toIso8601String(),
          'ble_supports_mesh': true,
        },
        onConflict: 'device_id',
      );
    } catch (e) {
      // Log but don't fail - device registration is not critical
      // The sync function will create the device if needed
    }
  }

  /// Sync all unsynced packets to Supabase
  Future<SyncResult> syncPendingPackets() async {
    // Prevent concurrent syncs
    if (_isSyncing) {
      return SyncResult(synced: 0, failed: 0, duplicates: 0);
    }

    // Check connectivity
    if (!_connectivity.isOnline) {
      return SyncResult(synced: 0, failed: 0, duplicates: 0, offline: true);
    }

    _isSyncing = true;
    _updateStatus(SyncStatus.syncing);

    int synced = 0;
    int failed = 0;
    int duplicates = 0;
    final syncedIds = <int>[];

    try {
      final packets = await _packetStore.getUnsyncedPackets();

      if (packets.isEmpty) {
        _updateStatus(SyncStatus.completed);
        _isSyncing = false;
        return SyncResult(synced: 0, failed: 0, duplicates: 0);
      }

      // Get my device ID for relay tracking
      final myUserId = await _packetStore.getUserId();
      final myDeviceId = myUserId.toRadixString(16).padLeft(8, '0');

      for (final packet in packets) {
        try {
          final result = await _syncPacket(packet, myDeviceId);

          if (result['success'] == true) {
            if (packet.dbId != null) {
              syncedIds.add(packet.dbId!);
            }

            if (result['is_new'] == true) {
              synced++;
            } else {
              duplicates++;
            }
          } else {
            failed++;
          }
        } catch (e) {
          failed++;
        }
      }

      // Mark all successfully synced packets
      if (syncedIds.isNotEmpty) {
        await _packetStore.markSynced(syncedIds);
      }

      _lastSyncTime = DateTime.now();
      _lastSyncController.add(_lastSyncTime);
      _updateStatus(SyncStatus.completed);
    } catch (e) {
      _updateStatus(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }

    return SyncResult(synced: synced, failed: failed, duplicates: duplicates);
  }

  /// Sync a single packet using the database function
  Future<Map<String, dynamic>> _syncPacket(
    SOSPacket packet,
    String deliveredBy,
  ) async {
    final deviceId = packet.userId.toRadixString(16).padLeft(8, '0');
    final messageId = '${deviceId}_${packet.sequence}';

    // Determine hop count (0 if we're the originator, 1+ if relayed)
    final isRelayed = packet.userId != int.parse(deliveredBy, radix: 16);
    final hopCount = isRelayed ? 1 : 0;

    final response = await client.rpc(
      'sync_sos_packet',
      params: {
        'p_message_id': messageId,
        'p_device_id': deviceId,
        'p_latitude': packet.latitude,
        'p_longitude': packet.longitude,
        'p_status_code': packet.status.code,
        'p_timestamp': packet.timestamp,
        'p_rssi': packet.rssi,
        'p_delivered_by': deliveredBy,
        'p_hop_count': hopCount,
      },
    );

    if (response is List && response.isNotEmpty) {
      return response.first as Map<String, dynamic>;
    }

    return {'success': false};
  }

  /// Update device heartbeat (call periodically when app is active)
  Future<void> updateHeartbeat() async {
    if (!_isInitialized || !_connectivity.isOnline) return;

    try {
      final userId = await _packetStore.getUserId();
      final deviceId = userId.toRadixString(16).padLeft(8, '0');

      await client.from('devices').update({
        'last_seen': DateTime.now().toUtc().toIso8601String(),
        'is_active': true,
      }).eq('device_id', deviceId);
    } catch (e) {
      // Ignore heartbeat failures
    }
  }

  /// Update device location in cloud
  Future<void> updateLocation(
    double latitude,
    double longitude, {
    double? accuracy,
  }) async {
    if (!_isInitialized || !_connectivity.isOnline) return;

    try {
      final userId = await _packetStore.getUserId();
      final deviceId = userId.toRadixString(16).padLeft(8, '0');

      // PostGIS POINT format: 'POINT(longitude latitude)'
      await client.from('devices').update({
        'last_known_location': 'POINT($longitude $latitude)',
        'location_accuracy': accuracy,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('device_id', deviceId);
    } catch (e) {
      // Ignore location update failures
    }
  }

  /// Get active alerts from cloud (for displaying global view)
  Future<List<Map<String, dynamic>>> getActiveAlerts({int limit = 100}) async {
    if (!_isInitialized) return [];

    try {
      final response = await client
          .from('sos_alerts')
          .select()
          .inFilter('status', ['active', 'acknowledged', 'responding'])
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('priority', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Get alert statistics
  Future<Map<String, dynamic>?> getAlertStats() async {
    if (!_isInitialized) return null;

    try {
      final response = await client.rpc('get_alert_stats');
      if (response is List && response.isNotEmpty) {
        return response.first as Map<String, dynamic>;
      }
    } catch (e) {
      // Ignore stats failures
    }
    return null;
  }

  /// Update sync status and notify listeners
  void _updateStatus(SyncStatus status) {
    _currentStatus = status;
    _syncStatusController.add(status);
  }

  /// Force a sync now (for manual refresh)
  Future<SyncResult> forceSyncNow() async {
    return syncPendingPackets();
  }

  /// Dispose resources
  void dispose() {
    _syncTimer?.cancel();
    _connectivitySub?.cancel();
    _syncStatusController.close();
    _lastSyncController.close();
  }
}
