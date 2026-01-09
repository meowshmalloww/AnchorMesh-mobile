import 'package:flutter/material.dart';
import '../models/sos_packet.dart';
import '../models/sos_status.dart';
import '../services/packet_store.dart';

class AlertsHistoryPage extends StatefulWidget {
  const AlertsHistoryPage({super.key});

  @override
  State<AlertsHistoryPage> createState() => _AlertsHistoryPageState();
}

class _AlertsHistoryPageState extends State<AlertsHistoryPage> {
  final PacketStore _packetStore = PacketStore.instance;
  List<SOSPacket> _historyPackets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final packets = await _packetStore.getHistoryPackets();
    if (mounted) {
      setState(() {
        _historyPackets = packets;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearHistory() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History?'),
        content: const Text('This will permanently delete all alert history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final deleted = await _packetStore.clearHistory();
      await _loadHistory(); // Refresh the list
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Cleared $deleted history entries')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alert History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _historyPackets.isEmpty ? null : _clearHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _historyPackets.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _historyPackets.length,
              itemBuilder: (context, index) {
                return _buildHistoryCard(_historyPackets[index], isDark);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No alert history',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(SOSPacket packet, bool isDark) {
    // We don't have isArchived on model yet, but packet store returns it.
    // We can interpret expiration.
    final isActive = !packet.isExpired && packet.status != SOSStatus.safe;
    final color = Color(packet.status.colorValue);
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      packet.timestamp * 1000,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(50),
          child: Icon(packet.status.icon, color: color, size: 20),
        ),
        title: Row(
          children: [
            Text(
              packet.status.description,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (!isActive) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'ARCHIVED',
                  style: TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'User: ${packet.userId.toRadixString(16).toUpperCase()}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              '${timestamp.year}-${timestamp.month}-${timestamp.day} ${timestamp.hour}:${timestamp.minute}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Icon(Icons.location_on, color: Colors.grey[400], size: 16),
      ),
    );
  }
}
