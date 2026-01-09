import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/sos_packet.dart';
import '../models/sos_status.dart';

/// Local SQLite storage for SOS packets
/// Implements store-and-forward pattern for mesh networking
class PacketStore {
  static PacketStore? _instance;
  static Database? _database;
  static Completer<Database>? _initCompleter;

  PacketStore._();

  static PacketStore get instance {
    _instance ??= PacketStore._();
    return _instance!;
  }

  /// Reset database connection for app restart (iOS force quit recovery)
  /// This clears stale database handles that persist across Dart VM restarts on iOS
  static Future<void> reset() async {
    // Wait for any pending initialization to complete first
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      try {
        await _initCompleter!.future;
      } catch (_) {
        // Ignore - we're resetting anyway
      }
    }
    _initCompleter = null;

    if (_database != null) {
      try {
        await _database!.close();
      } catch (_) {
        // Ignore close errors - database may already be closed/invalid
      }
      _database = null;
    }
  }

  /// Get database instance (thread-safe with lock)
  Future<Database> get database async {
    // Fast path: already initialized
    if (_database != null) return _database!;

    // Check if initialization is in progress
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    // Start initialization with lock
    _initCompleter = Completer<Database>();
    try {
      _database = await _initDatabase();
      _initCompleter!.complete(_database!);
      return _database!;
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'sos_packets.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Version 2: Add targetId for direct messaging
      await db.execute(
        'ALTER TABLE packets ADD COLUMN targetId INTEGER DEFAULT 0',
      );
    }
  }

  /// Create tables
  Future<void> _onCreate(Database db, int version) async {
    // Received packets from mesh
    await db.execute('''
      CREATE TABLE packets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL,
        sequence INTEGER NOT NULL,
        latitudeE7 INTEGER NOT NULL,
        longitudeE7 INTEGER NOT NULL,
        status INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        rssi INTEGER,
        isSynced INTEGER DEFAULT 0,
        targetId INTEGER DEFAULT 0,
        receivedAt INTEGER NOT NULL,
        isArchived INTEGER DEFAULT 0,
        UNIQUE(userId, sequence)
      )
    ''');

    // Broadcast queue (packets to relay)
    await db.execute('''
      CREATE TABLE broadcast_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        packetId INTEGER NOT NULL,
        priority INTEGER DEFAULT 0,
        addedAt INTEGER NOT NULL,
        FOREIGN KEY (packetId) REFERENCES packets(id)
      )
    ''');

    // Seen packet IDs (for deduplication)
    await db.execute('''
      CREATE TABLE seen_packets (
        uniqueId TEXT PRIMARY KEY,
        seenAt INTEGER NOT NULL
      )
    ''');

    // Local user settings
    await db.execute('''
      CREATE TABLE user_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_packets_user ON packets(userId)');
    await db.execute(
      'CREATE INDEX idx_packets_timestamp ON packets(timestamp)',
    );
    await db.execute('CREATE INDEX idx_packets_synced ON packets(isSynced)');
  }

  // ==================
  // Packet Operations
  // ==================

  /// Save a received packet (with deduplication)
  /// Returns true if packet was new and saved
  Future<bool> savePacket(SOSPacket packet) async {
    final db = await database;

    try {
      if (await hasSeenPacket(packet.uniqueId)) {
        // Check if this is a newer sequence from same user
        final existing = await getPacketByUserId(packet.userId);
        if (existing != null && packet.sequence > existing.sequence) {
          // Update to newer version
          await db.update(
            'packets',
            packet.toJson()
              ..['receivedAt'] = DateTime.now().millisecondsSinceEpoch,
            where: 'userId = ?',
            whereArgs: [packet.userId],
          );
          await _markSeen(packet.uniqueId);
          return true;
        }
        return false; // Duplicate, ignore
      }

      // Check if expired
      if (packet.isExpired) {
        return false;
      }

      // Insert new packet
      await db.insert(
        'packets',
        packet.toJson()..['receivedAt'] = DateTime.now().millisecondsSinceEpoch,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Mark seen immediately
      await _markSeen(packet.uniqueId);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if we've seen this packet ID before
  Future<bool> hasSeenPacket(String uniqueId) async {
    final db = await database;
    final result = await db.query(
      'seen_packets',
      where: 'uniqueId = ?',
      whereArgs: [uniqueId],
    );
    return result.isNotEmpty;
  }

  /// Mark packet as seen
  Future<void> _markSeen(String uniqueId) async {
    final db = await database;
    await db.insert('seen_packets', {
      'uniqueId': uniqueId,
      'seenAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get packet by user ID
  Future<SOSPacket?> getPacketByUserId(int userId) async {
    final db = await database;
    final result = await db.query(
      'packets',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'sequence DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return SOSPacket.fromJson(result.first);
  }

  /// Get all active (non-expired, non-safe) packets
  Future<List<SOSPacket>> getActivePackets() async {
    final db = await database;
    final cutoff =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - SOSPacket.maxAgeSeconds;
    final result = await db.query(
      'packets',
      where: 'timestamp > ? AND status != ? AND isArchived = 0',
      whereArgs: [cutoff, SOSStatus.safe.code],
      orderBy: 'timestamp DESC',
    );
    return result.map((r) => SOSPacket.fromJson(r)).toList();
  }

  /// Get all history packets (including archived)
  Future<List<SOSPacket>> getHistoryPackets() async {
    final db = await database;
    final result = await db.query('packets', orderBy: 'receivedAt DESC');
    return result.map((r) => SOSPacket.fromJson(r)).toList();
  }

  /// Get unsynced packets for cloud upload
  Future<List<SOSPacket>> getUnsyncedPackets() async {
    final db = await database;
    final result = await db.query(
      'packets',
      where: 'isSynced = 0',
      orderBy: 'timestamp ASC',
    );
    return result.map((r) => SOSPacket.fromJson(r)).toList();
  }

  /// Mark packets as synced
  Future<void> markSynced(List<int> packetIds) async {
    if (packetIds.isEmpty) return;
    final db = await database;
    // Use parameterized query to prevent SQL injection
    final placeholders = List.filled(packetIds.length, '?').join(',');
    await db.update(
      'packets',
      {'isSynced': 1},
      where: 'id IN ($placeholders)',
      whereArgs: packetIds,
    );
  }

  /// Delete old packets (cleanup)
  Future<int> deleteExpiredPackets() async {
    final db = await database;
    final cutoff =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - SOSPacket.maxAgeSeconds;

    // Archive expired packets instead of deleting
    final archivedCount = await db.update(
      'packets',
      {'isArchived': 1},
      where: 'timestamp < ? AND isArchived = 0',
      whereArgs: [cutoff],
    );

    // Delete very old history (e.g. > 30 days) to save space
    final historyCutoff =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - (86400 * 30);
    await db.delete(
      'packets',
      where: 'timestamp < ?',
      whereArgs: [historyCutoff],
    );

    // Delete old seen entries (keep last 24 hours)
    final seenCutoff =
        DateTime.now().millisecondsSinceEpoch -
        (SOSPacket.maxAgeSeconds * 1000);
    await db.delete(
      'seen_packets',
      where: 'seenAt < ?',
      whereArgs: [seenCutoff],
    );

    return archivedCount;
  }

  /// Get storage usage in bytes (estimate)
  Future<int> getStorageSize() async {
    final db = await database;
    final path = db.path;
    try {
      final file = File(path); // Requires dart:io
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Clear all local data (packets, seen entries, queue)
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('packets');
      await txn.delete('seen_packets');
      await txn.delete('broadcast_queue');
    });
  }

  /// Clear history only (archived + expired packets, keep active ones)
  Future<int> clearHistory() async {
    final db = await database;
    final cutoff =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - SOSPacket.maxAgeSeconds;

    // Delete archived or expired packets
    return await db.delete(
      'packets',
      where: 'isArchived = 1 OR timestamp < ? OR status = ?',
      whereArgs: [cutoff, SOSStatus.safe.index],
    );
  }

  // ==================
  // Broadcast Queue
  // ==================

  /// Add packet to broadcast queue
  Future<void> addToQueue(int packetId, {int priority = 0}) async {
    final db = await database;
    await db.insert('broadcast_queue', {
      'packetId': packetId,
      'priority': priority,
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Get next packet to broadcast (highest priority first)
  Future<SOSPacket?> getNextBroadcast() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT p.* FROM packets p
      INNER JOIN broadcast_queue q ON p.id = q.packetId
      ORDER BY q.priority DESC, q.addedAt ASC
      LIMIT 1
    ''');
    if (result.isEmpty) return null;
    return SOSPacket.fromJson(result.first);
  }

  /// Remove packet from broadcast queue
  Future<void> removeFromQueue(int packetId) async {
    final db = await database;
    await db.delete(
      'broadcast_queue',
      where: 'packetId = ?',
      whereArgs: [packetId],
    );
  }

  /// Clear entire broadcast queue
  Future<void> clearQueue() async {
    final db = await database;
    await db.delete('broadcast_queue');
  }

  // ==================
  // User Settings
  // ==================

  /// Get user ID (generate if not exists)
  Future<int> getUserId() async {
    final db = await database;
    final result = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: ['userId'],
    );

    if (result.isNotEmpty) {
      return int.parse(result.first['value'] as String);
    }

    // Generate new user ID
    final userId = SOSPacket.generateUserId();
    await db.insert('user_settings', {
      'key': 'userId',
      'value': userId.toString(),
    });
    return userId;
  }

  /// Get current sequence number
  Future<int> getSequence() async {
    final db = await database;
    final result = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: ['sequence'],
    );

    if (result.isNotEmpty) {
      return int.parse(result.first['value'] as String);
    }
    return 0;
  }

  /// Increment and get sequence number
  Future<int> incrementSequence() async {
    final current = await getSequence();
    final next = current + 1;
    final db = await database;
    await db.insert('user_settings', {
      'key': 'sequence',
      'value': next.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return next;
  }

  /// Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
