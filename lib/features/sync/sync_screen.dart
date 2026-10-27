import 'package:flutter/material.dart';

import '../../core/local_db.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';

const _conflictText = {
  'NEGATIVE_STOCK': 'Not enough stock for this order',
  'VALIDATION_FAILED': 'The item is no longer valid',
  'SERVER_ERROR': 'Server error while applying',
  'ITEM_UNAVAILABLE': 'An item is unavailable',
  'SHIFT_CLOSED': 'The shift was already closed',
  'FORBIDDEN': 'Your role cannot do this',
};

/// Offline queue: what is waiting to upload and what the server rejected.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  late Future<List<OutboxItem>> _items;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _items = AppScope.read(context).db.outbox();
  }

  void _reload() => setState(() => _items = AppScope.read(context).db.outbox());

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: FutureBuilder<List<OutboxItem>>(
        future: _items,
        builder: (context, snap) {
          final items = snap.data ?? const [];
          return ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Column(children: [
                ListTile(
                  leading: Icon(app.online ? Icons.cloud_done : Icons.cloud_off, color: app.online ? Brand.success : Brand.warning),
                  title: Text(app.online ? 'Online' : 'Offline'),
                  subtitle: Text(app.lastSyncAt == null ? 'Not synced yet' : 'Last sync ${fmtDate(app.lastSyncAt!.toIso8601String())}'),
                ),
                ListTile(
                  title: Text('${app.pendingCount} waiting, ${app.conflictCount} need attention'),
                  subtitle: Text('Menu data version ${app.dataVersion}'),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: app.syncing
                  ? null
                  : () async {
                      await app.syncNow();
                      _reload();
                    },
              icon: const Icon(Icons.sync),
              label: Text(app.syncing ? 'Syncing...' : 'Sync now'),
            ),
            const SectionTitle('Queue'),
            if (items.isEmpty) const EmptyState('Everything is uploaded.'),
            for (final o in items)
              Card(
                child: ListTile(
                  leading: Icon(_icon(o.type), color: statusColor(o.status.name)),
                  title: Text(o.label ?? titleCase(o.type)),
                  subtitle: Text(
                    '${fmtDate(o.createdAtDevice)}'
                    '${o.status == OutboxStatus.conflict ? '\n${_conflictText[o.reason] ?? o.reason ?? 'Rejected'}' : ''}',
                  ),
                  isThreeLine: o.status == OutboxStatus.conflict,
                  trailing: o.status == OutboxStatus.conflict
                      ? PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'retry') {
                              await app.db.resetPending(o.clientId);
                            } else {
                              await app.db.deleteOutbox(o.clientId);
                            }
                            await app.refreshPending();
                            if (v == 'retry') {
                              await app.syncNow();
                            }
                            _reload();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'retry', child: Text('Try again')),
                            PopupMenuItem(value: 'discard', child: Text('Discard')),
                          ],
                        )
                      : StatusChip(o.status.name),
                ),
              ),
          ]);
        },
      ),
    );
  }

  IconData _icon(String type) => switch (type) {
        'order' => Icons.receipt_long,
        'payment' => Icons.payments,
        'shift' => Icons.savings,
        'wastage' => Icons.delete_sweep,
        'stock_count' => Icons.fact_check,
        _ => Icons.cloud_upload,
      };
}
