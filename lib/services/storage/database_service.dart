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
      // Check if message already exists (deduplication)
      final existing = await db.query(
        'messages',
        where: 'message_id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      
      if (existing.isNotEmpty) {
        return false; // Already have this message
      }
      
      // Insert new message
      await db.insert(
        'messages',
        {
          'message_id': messageId,
          'packet_data': packetData,
          'status': 'pending',
          'received_at': DateTime.now().millisecondsSinceEpoch,
          'hop_count': hopCount,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      
      return true; // New message saved
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
