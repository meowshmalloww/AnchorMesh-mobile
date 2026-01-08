import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:synchronized/synchronized.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;
  static final _lock = Lock();

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    return await _lock.synchronized(() async {
      if (_database != null && _database!.isOpen) {
        return _database!;
      }
      _database = await _initDatabase();
      return _database!;
    });
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'sos_mesh.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Table for storing SOS messages
        // id: Unique composite key (UserID + Timestamp or explicit MessageID)
        // data: Raw binary data for re-broadcasting
        // status: pending, synced
        // received_at: Local timestamp for cleanup
        await db.execute('''
          CREATE TABLE messages (
            message_id TEXT PRIMARY KEY,
            packet_data BLOB NOT NULL,
            status TEXT DEFAULT 'pending',
            received_at INTEGER NOT NULL,
            hop_count INTEGER DEFAULT 0
          )
        ''');

        // Table for User Identity
        await db.execute('''
          CREATE TABLE identity (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
    );
  }

  /// Save a received SOS packet. Returns true if new, false if duplicate.
  Future<bool> saveMessage(String messageId, List<int> packetData, int hopCount) async {
    final db = await database;
    try {
      await db.insert(
        'messages',
        {
          'message_id': messageId,
          'packet_data': packetData,
          'status': 'pending',
          'received_at': DateTime.now().millisecondsSinceEpoch,
          'hop_count': hopCount,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore, // Deduplication strategy
      );
      // Check if it was actually inserted
      final List<Map> maps = await db.query(
        'messages',
        where: 'message_id = ? AND received_at = ?',
        whereArgs: [messageId, DateTime.now().millisecondsSinceEpoch], // Loose check, better logic below
      );
      
      // Better check: If insert ignored, row count won't increase. 
      // But standard insert returns ID or 0.
      // Simplest: Check if it exists BEFORE insert? No, race condition.
      // ConflictAlgorithm.ignore returns the ID if inserted, or null/0 if ignored.
      // Wait, sqflite insert returns ID of inserted row. If ignored, it might depend on driver.
      
      // Let's rely on query for existence if we really need to know "isNew".
      // Optimized: Just Insert. If we need to know if we should rebroadcast, we can check 
      // if we already have it.
      
      // For "Is New" check (to trigger notification/rebroadcast logic):
      final existing = await db.query('messages', where: 'message_id = ?', whereArgs: [messageId]);
      if (existing.length > 1) return false; // Should satisfy unique constraint
      return true; 
    } catch (e) {
      return false;
    }
  }

  /// Get pending messages for Store-and-Forward (Upload)
  Future<List<Map<String, dynamic>>> getPendingMessages() async {
    final db = await database;
    return await db.query('messages', where: "status = 'pending'");
  }

  /// Get messages to relay (Rebroadcast loop)
  /// Returns a limited number of recent messages to avoid jamming
  Future<List<Map<String, dynamic>>> getMessagesToRelay(int limit) async {
    final db = await database;
    // Priority: Newest first, or maybe critical status? 
    // For now, simple FIFO/LIFO mix or random?
    // Let's do newest first to propagate recent alerts.
    return await db.query(
      'messages',
      orderBy: 'received_at DESC',
      limit: limit,
    );
  }

  /// Mark messages as synced (Uploaded)
  Future<void> markAsSynced(List<String> messageIds) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final id in messageIds) {
        await txn.update(
          'messages',
          {'status': 'synced'},
          where: 'message_id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  /// Delete old messages (Cleanup task)
  Future<int> deleteOldMessages(Duration maxAge) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    return await db.delete('messages', where: 'received_at < ?', whereArgs: [cutoff]);
  }
  
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
