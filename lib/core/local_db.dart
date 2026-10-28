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

/// An order made on this device, kept as a printable snapshot.
///
/// [kind] is `order` for a new sale and `edit` for a revision of an order
/// that already lives on the server; [clientId] matches the outbox item
/// that will carry it to the server.
class LocalOrder {
  LocalOrder({
    required this.clientId,
    required this.kind,
    required this.invoiceNo,
    required this.order,
    required this.createdAt,
    this.tokenNo,
    this.synced = false,
    this.serverId,
  });

  final String clientId;
  final String kind;
  final String invoiceNo;
  final String? tokenNo;
  final Map<String, dynamic> order;
  final bool synced;
  final int? serverId;
  final String createdAt;

  Map<String, Object?> toRow() => {
    'client_id': clientId,
    'kind': kind,
    'invoice_no': invoiceNo,
    'token_no': tokenNo,
    'order_json': jsonEncode(order),
    'synced': synced ? 1 : 0,
    'server_id': serverId,
    'created_at': createdAt,
  };

  static LocalOrder fromRow(Map<String, Object?> r) => LocalOrder(
    clientId: r['client_id']! as String,
    kind: r['kind']! as String,
    invoiceNo: r['invoice_no']! as String,
    tokenNo: r['token_no'] as String?,
    order: Map<String, dynamic>.from(
      jsonDecode(r['order_json']! as String) as Map,
    ),
    synced: (r['synced'] as int?) == 1,
    serverId: r['server_id'] as int?,
    createdAt: r['created_at']! as String,
  );

  LocalOrder copyWith({Map<String, dynamic>? order, String? invoiceNo}) =>
      LocalOrder(
        clientId: clientId,
        kind: kind,
        invoiceNo: invoiceNo ?? this.invoiceNo,
        tokenNo: tokenNo,
        order: order ?? this.order,
        createdAt: createdAt,
        synced: synced,
        serverId: serverId,
      );
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
      version: 2,
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await _createOfflineTables(db);
        }
      },
      onCreate: (db, _) async {
        await _createOfflineTables(db);
        await db.execute(
          'CREATE TABLE cache (k TEXT PRIMARY KEY, body TEXT NOT NULL, saved_at TEXT NOT NULL)',
        );
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

  static Future<void> _createOfflineTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_orders (
        client_id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        invoice_no TEXT NOT NULL,
        token_no TEXT,
        order_json TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        server_id INTEGER,
        created_at TEXT NOT NULL
      )''');
    await db.execute(
      'CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL)',
    );
  }

  Future<void> putCache(String key, Object? data) async {
    await _db.insert('cache', {
      'k': key,
      'body': jsonEncode(data),
      'saved_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
        .map(
          (r) => OutboxItem(
            clientId: r['client_id']! as String,
            type: r['type']! as String,
            payload:
                jsonDecode(r['payload']! as String) as Map<String, dynamic>,
            createdAtDevice: r['created_at_device']! as String,
            dataVersion: r['data_version'] as int?,
            status: OutboxStatus.values.byName(r['status']! as String),
            reason: r['reason'] as String?,
            label: r['label'] as String?,
          ),
        )
        .toList();
  }

  Future<void> markOutbox(
    String clientId,
    OutboxStatus status, {
    String? reason,
  }) async {
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

  /// Replaces the payload of a queued item that has not been sent yet.
  Future<void> updateOutboxPayload(
    String clientId,
    Map<String, dynamic> payload, {
    String? label,
  }) => _db.update(
    'outbox',
    {'payload': jsonEncode(payload), 'label': ?label},
    where: "client_id = ? AND status = 'pending'",
    whereArgs: [clientId],
  );

  Future<OutboxItem?> outboxItem(String clientId) async =>
      (await outbox()).where((o) => o.clientId == clientId).firstOrNull;

  // ------------------------------------------------------- local orders

  /// Saves a receipt snapshot of an order made or revised on this device,
  /// so it can be shown and printed with no network.
  Future<void> saveLocalOrder(LocalOrder order) => _db.insert(
    'local_orders',
    order.toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<LocalOrder?> localOrder(String clientId) async {
    final rows = await _db.query(
      'local_orders',
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
    return rows.isEmpty ? null : LocalOrder.fromRow(rows.first);
  }

  Future<List<LocalOrder>> localOrders({bool? synced, String? kind}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (synced != null) {
      where.add('synced = ?');
      args.add(synced ? 1 : 0);
    }
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    final rows = await _db.query(
      'local_orders',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(LocalOrder.fromRow).toList();
  }

  Future<void> markLocalOrderSynced(
    String clientId, {
    String? invoiceNo,
    int? serverId,
  }) async {
    final order = await localOrder(clientId);
    if (order == null) {
      return;
    }
    final snapshot = Map<String, dynamic>.from(order.order);
    if (invoiceNo != null) {
      snapshot['invoice_no'] = invoiceNo;
    }
    await _db.update(
      'local_orders',
      {
        'synced': 1,
        'invoice_no': invoiceNo ?? order.invoiceNo,
        'server_id': serverId ?? order.serverId,
        'order_json': jsonEncode(snapshot),
      },
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// Synced snapshots are only kept for a short while; the server has them.
  Future<void> purgeOldSyncedOrders({
    Duration keep = const Duration(days: 3),
  }) => _db.delete(
    'local_orders',
    where: 'synced = 1 AND created_at < ?',
    whereArgs: [DateTime.now().subtract(keep).toUtc().toIso8601String()],
  );

  // ----------------------------------------------------------------- meta

  Future<String?> meta(String key) async {
    final rows = await _db.query('meta', where: 'k = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['v'] as String;
  }

  Future<void> setMeta(String key, String value) => _db.insert('meta', {
    'k': key,
    'v': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> wipe() async {
    await _db.delete('cache');
    await _db.delete('outbox');
    await _db.delete('local_orders');
  }
}
