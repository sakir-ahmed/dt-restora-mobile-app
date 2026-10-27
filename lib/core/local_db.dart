import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

enum OutboxStatus { pending, accepted, duplicate, conflict }

class OutboxItem {
  OutboxItem({
    required this.clientId,
    required this.type,
    required this.payload,
    required this.createdAtDevice,
    required this.dataVersion,
    required this.status,
    this.reason,
    this.label,
  });

  final String clientId;
  final String type;
  final Map<String, dynamic> payload;
  final String createdAtDevice;
  final int? dataVersion;
  final OutboxStatus status;
  final String? reason;
  final String? label;

  Map<String, dynamic> toPushJson() => {
        'client_id': clientId,
        'type': type,
        'payload': payload,
        'created_at_device': createdAtDevice,
        if (dataVersion != null) 'data_version': dataVersion,
      };
}

/// Device storage: a JSON cache for read-through GETs and an outbox of
/// offline writes waiting for `/sync/push`.
class LocalDb {
  LocalDb._(this._db);

  final Database _db;

  static Future<LocalDb> open() async {
    final path = p.join(await getDatabasesPath(), 'dt_restora.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
            'CREATE TABLE cache (k TEXT PRIMARY KEY, body TEXT NOT NULL, saved_at TEXT NOT NULL)');
        await db.execute('''
          CREATE TABLE outbox (
            client_id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at_device TEXT NOT NULL,
            data_version INTEGER,
            status TEXT NOT NULL,
            reason TEXT,
            label TEXT
          )''');
      },
    );
    return LocalDb._(db);
  }

  Future<void> putCache(String key, Object? data) async {
    await _db.insert(
      'cache',
      {'k': key, 'body': jsonEncode(data), 'saved_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<({dynamic data, DateTime savedAt})?> getCache(String key) async {
    final rows = await _db.query('cache', where: 'k = ?', whereArgs: [key]);
    if (rows.isEmpty) {
      return null;
    }
    return (
      data: jsonDecode(rows.first['body']! as String),
      savedAt: DateTime.parse(rows.first['saved_at']! as String),
    );
  }

  Future<void> clearCache() => _db.delete('cache');

  Future<void> enqueue(OutboxItem item) async {
    await _db.insert('outbox', {
      'client_id': item.clientId,
      'type': item.type,
      'payload': jsonEncode(item.payload),
      'created_at_device': item.createdAtDevice,
      'data_version': item.dataVersion,
      'status': item.status.name,
      'reason': item.reason,
      'label': item.label,
    });
  }

  Future<List<OutboxItem>> outbox({OutboxStatus? status}) async {
    final rows = await _db.query(
      'outbox',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status.name],
      orderBy: 'created_at_device ASC',
    );
    return rows
        .map((r) => OutboxItem(
              clientId: r['client_id']! as String,
              type: r['type']! as String,
              payload: jsonDecode(r['payload']! as String) as Map<String, dynamic>,
              createdAtDevice: r['created_at_device']! as String,
              dataVersion: r['data_version'] as int?,
              status: OutboxStatus.values.byName(r['status']! as String),
              reason: r['reason'] as String?,
              label: r['label'] as String?,
            ))
        .toList();
  }

  Future<void> markOutbox(String clientId, OutboxStatus status, {String? reason}) async {
    await _db.update(
      'outbox',
      {'status': status.name, 'reason': reason},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// Accepted and duplicate items are done; drop them from the device.
  Future<void> purgeDone() =>
      _db.delete('outbox', where: "status IN ('accepted','duplicate')");

  Future<void> deleteOutbox(String clientId) =>
      _db.delete('outbox', where: 'client_id = ?', whereArgs: [clientId]);

  Future<void> resetPending(String clientId) =>
      markOutbox(clientId, OutboxStatus.pending);

  Future<void> wipe() async {
    await _db.delete('cache');
    await _db.delete('outbox');
  }
}
