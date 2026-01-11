import 'dart:async';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import '../services/packet_store.dart';

/// A widget that displays the current sync status with Supabase cloud
class SyncStatusWidget extends StatefulWidget {
  final bool compact;
  final bool showSyncButton;

  const SyncStatusWidget({
    super.key,
    this.compact = false,
    this.showSyncButton = true,
  });

  @override
  State<SyncStatusWidget> createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget>
    with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService.instance;
  final ConnectivityChecker _connectivity = ConnectivityChecker.instance;
  final PacketStore _packetStore = PacketStore.instance;

  SyncStatus _syncStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  bool _isOnline = false;
  int _pendingCount = 0;
  String? _errorMessage;

  late AnimationController _rotationController;
  StreamSubscription<SyncStatus>? _statusSub;
  StreamSubscription<DateTime?>? _lastSyncSub;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _setupListeners();
    _loadPendingCount();
  }

  void _setupListeners() {
    _statusSub = _supabaseService.syncStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _syncStatus = status;
          if (status == SyncStatus.error) {
            _errorMessage = 'Sync failed. Will retry automatically.';
          } else {
            _errorMessage = null;
          }
        });
        if (status == SyncStatus.syncing) {
          _rotationController.repeat();
        } else {
          _rotationController.stop();
          _rotationController.reset();
        }
      }
    });

    _lastSyncSub = _supabaseService.lastSyncStream.listen((time) {
      if (mounted) {
        setState(() => _lastSyncTime = time);
        _loadPendingCount();
      }
    });

    _connectivitySub = _connectivity.statusStream.listen((online) {
      if (mounted) {
        setState(() => _isOnline = online);
      }
    });

    // Initial state
    setState(() {
      _syncStatus = _supabaseService.currentStatus;
      _lastSyncTime = _supabaseService.lastSyncTime;
      _isOnline = _connectivity.isOnline;
    });
  }

  Future<void> _loadPendingCount() async {
    final packets = await _packetStore.getUnsyncedPackets();
    if (mounted) {
      setState(() => _pendingCount = packets.length);
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _statusSub?.cancel();
    _lastSyncSub?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _triggerSync() async {
    if (_syncStatus == SyncStatus.syncing) return;
    if (!_isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No internet connection. Connect to sync.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final result = await _supabaseService.forceSyncNow();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.synced > 0
                ? 'Synced ${result.synced} packet${result.synced == 1 ? '' : 's'} to cloud'
                : result.offline
                    ? 'Offline - will sync when connected'
                    : 'All data is already synced',
          ),
          backgroundColor: result.synced > 0 ? Colors.green : Colors.grey,
        ),
      );
    }
  }

  String _getLastSyncText() {
    if (_lastSyncTime == null) return 'Never synced';
    final diff = DateTime.now().difference(_lastSyncTime!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  IconData _getStatusIcon() {
    switch (_syncStatus) {
      case SyncStatus.syncing:
        return Icons.sync;
      case SyncStatus.completed:
        return Icons.cloud_done;
      case SyncStatus.error:
        return Icons.cloud_off;
      case SyncStatus.idle:
        return _isOnline ? Icons.cloud_queue : Icons.cloud_off;
    }
  }

  Color _getStatusColor() {
    switch (_syncStatus) {
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.completed:
        return Colors.green;
      case SyncStatus.error:
        return Colors.red;
      case SyncStatus.idle:
        return _isOnline ? Colors.grey : Colors.orange;
    }
  }

  String _getStatusText() {
    switch (_syncStatus) {
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.completed:
        return 'Synced';
      case SyncStatus.error:
        return 'Sync Error';
      case SyncStatus.idle:
        return _isOnline ? 'Ready' : 'Offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _buildCompact();
    }
    return _buildFull();
  }

  Widget _buildCompact() {
    return InkWell(
      onTap: _triggerSync,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _getStatusColor().withAlpha(30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _getStatusColor().withAlpha(50)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _rotationController,
              child: Icon(
                _getStatusIcon(),
                size: 16,
                color: _getStatusColor(),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _getStatusText(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _getStatusColor(),
              ),
            ),
            if (_pendingCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: _getStatusColor(),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$_pendingCount',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFull() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withAlpha(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _getStatusColor().withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: RotationTransition(
                    turns: _rotationController,
                    child: Icon(
                      _getStatusIcon(),
                      color: _getStatusColor(),
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cloud Sync',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      _getStatusText(),
                      style: TextStyle(
                        fontSize: 12,
                        color: _getStatusColor(),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showSyncButton)
                IconButton(
                  onPressed:
                      _syncStatus != SyncStatus.syncing ? _triggerSync : null,
                  icon: Icon(
                    Icons.refresh,
                    color: _syncStatus != SyncStatus.syncing
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Stats Row
          Row(
            children: [
              _buildStatItem(
                icon: Icons.cloud_upload,
                label: 'Pending',
                value: '$_pendingCount',
                color: _pendingCount > 0 ? Colors.orange : Colors.green,
              ),
              const SizedBox(width: 16),
              _buildStatItem(
                icon: Icons.access_time,
                label: 'Last Sync',
                value: _getLastSyncText(),
                color: Colors.blue,
              ),
              const SizedBox(width: 16),
              _buildStatItem(
                icon: _isOnline ? Icons.wifi : Icons.wifi_off,
                label: 'Connection',
                value: _isOnline ? 'Online' : 'Offline',
                color: _isOnline ? Colors.green : Colors.orange,
              ),
            ],
          ),

          // Error message
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withAlpha(50)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
