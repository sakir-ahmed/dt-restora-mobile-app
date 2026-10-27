import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/config.dart';
import '../core/theme.dart';

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing to rebuilds.
  static AppState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
}

final _money = NumberFormat('#,##0.00');

String fmtMoney(Object? v) {
  final n = v is num ? v : num.tryParse('$v') ?? 0;
  return 'BDT ${_money.format(n)}';
}

double toNum(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

String fmtDate(Object? v) {
  final d = v == null ? null : DateTime.tryParse('$v')?.toLocal();
  return d == null ? '' : DateFormat('d MMM yyyy, h:mm a').format(d);
}

String fmtDay(Object? v) {
  final d = v == null ? null : DateTime.tryParse('$v')?.toLocal();
  return d == null ? '' : DateFormat('d MMM yyyy').format(d);
}

String titleCase(String s) => s
    .replaceAll('_', ' ')
    .replaceAll('-', ' ')
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// `name` or `name_bn` depending on the app language.
String localized(AppState app, Map m, [String key = 'name']) {
  if (app.locale == 'bn') {
    final bn = m['${key}_bn'];
    if (bn is String && bn.isNotEmpty) {
      return bn;
    }
  }
  return '${m[key] ?? ''}';
}

List<Map<String, dynamic>> asRows(Object? v) =>
    ((v as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

void snack(BuildContext context, String message, {bool error = false, String? actionLabel, VoidCallback? onAction}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: Duration(seconds: actionLabel == null ? 4 : 8),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, textColor: Brand.accent, onPressed: onAction ?? () {}),
    ));
}

Future<bool> confirm(BuildContext context, String title, {String? body, String action = 'Confirm'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Runs [action], showing API errors as a snackbar. Returns true on success.
Future<bool> guarded(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on ApiException catch (e) {
    if (context.mounted) {
      snack(context, e.fullMessage, error: true);
    }
    return false;
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'paid':
    case 'served':
    case 'delivered':
    case 'received':
    case 'approved':
    case 'posted':
    case 'accepted':
    case 'open':
      return Brand.success;
    case 'cancelled':
    case 'voided':
    case 'failed':
    case 'rejected':
    case 'conflict':
      return Brand.danger;
    case 'preparing':
    case 'on_the_way':
    case 'picked_up':
    case 'pending':
    case 'draft':
      return Brand.warning;
    default:
      return Brand.primary;
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        titleCase(status),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class Metric extends StatelessWidget {
  const Metric(this.label, this.value, {super.key, this.icon, this.negative = false});

  final String label;
  final String value;
  final IconData? icon;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 16, color: context.muted), const SizedBox(width: 6)],
              Expanded(child: Text(label, style: TextStyle(color: context.muted, fontSize: 12))),
            ]),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: negative ? Brand.danger : context.fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.color});

  final String text;
  final Widget? trailing;

  /// Accent bar shown before the title, e.g. the module group colour.
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Row(children: [
          if (color != null) ...[
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: context.fg)),
          ),
          ?trailing,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
        ),
      );
}

/// Slim persistent footer shown under every main screen. Gives content a
/// clear bottom bound and, with its SafeArea, keeps anything from hiding
/// behind the system gesture bar.
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final year = DateTime.now().year;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: context.lineColor)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(children: [
          Icon(
            app.online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: 13,
            color: app.online ? Brand.success : Brand.warning,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '© $year ${app.appName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: context.muted),
            ),
          ),
          Text('v${AppConfig.appVersion}', style: TextStyle(fontSize: 10.5, color: context.muted)),
        ]),
      ),
    );
  }
}

class OfflineNote extends StatelessWidget {
  const OfflineNote(this.savedAt, {super.key});

  final DateTime? savedAt;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: context.warnBg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Icon(Icons.cloud_off, size: 16, color: context.warnFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              savedAt == null
                  ? 'Offline: showing saved data'
                  : 'Offline: showing data saved ${DateFormat('d MMM, h:mm a').format(savedAt!)}',
              style: TextStyle(fontSize: 12, color: context.warnFg),
            ),
          ),
        ]),
      );
}

/// Loads a cached GET and renders [builder]; handles loading, errors,
/// the offline notice and pull-to-refresh.
class DataView<T> extends StatefulWidget {
  const DataView({
    super.key,
    required this.path,
    required this.builder,
    this.query,
    this.transform,
  });

  final String path;
  final Map<String, dynamic>? query;
  final T Function(dynamic raw)? transform;
  final Widget Function(BuildContext context, T data, Cached<dynamic> raw, Future<void> Function() reload)
      builder;

  @override
  State<DataView<T>> createState() => DataViewState<T>();
}

class DataViewState<T> extends State<DataView<T>> {
  Future<Cached<dynamic>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<Cached<dynamic>> _load() => AppScope.read(context).cachedGet(widget.path, query: widget.query);

  Future<void> reload() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } on ApiException {
      // Shown by the FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Cached<dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${snap.error}', textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
                const SizedBox(height: 16),
                OutlinedButton(onPressed: reload, child: const Text('Try again')),
              ]),
            ),
          );
        }
        final raw = snap.data!;
        final data = widget.transform != null ? widget.transform!(raw.data) : raw.data as T;
        return Column(children: [
          if (raw.fromCache) OfflineNote(raw.savedAt),
          Expanded(child: RefreshIndicator(onRefresh: reload, child: widget.builder(context, data, raw, reload))),
        ]);
      },
    );
  }
}

/// A scaffold + [DataView] list in one, the building block of most modules.
class ListModule extends StatefulWidget {
  const ListModule({
    super.key,
    required this.title,
    required this.path,
    required this.itemBuilder,
    this.query,
    this.extract,
    this.fab,
    this.actions,
    this.header,
  });

  final String title;
  final String path;
  final Map<String, dynamic>? query;
  final List<Map<String, dynamic>> Function(dynamic raw)? extract;
  final Widget Function(BuildContext context, Map<String, dynamic> row, Future<void> Function() reload)
      itemBuilder;
  final Widget Function(Future<void> Function() reload)? fab;
  final List<Widget>? actions;
  final Widget? header;

  @override
  State<ListModule> createState() => _ListModuleState();
}

class _ListModuleState extends State<ListModule> {
  final _key = GlobalKey<DataViewState<List<Map<String, dynamic>>>>();

  Future<void> _reload() async => _key.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: widget.actions),
      floatingActionButton: widget.fab?.call(_reload),
      body: DataView<List<Map<String, dynamic>>>(
        key: _key,
        path: widget.path,
        query: widget.query,
        transform: (raw) => widget.extract != null ? widget.extract!(raw) : asRows(raw),
        builder: (context, rows, raw, reload) {
          if (rows.isEmpty) {
            return ListView(children: const [SizedBox(height: 120), EmptyState('Nothing here yet.')]);
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: rows.length + (widget.header == null ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              if (widget.header != null) {
                if (i == 0) {
                  return widget.header!;
                }
                i -= 1;
              }
              return widget.itemBuilder(context, rows[i], reload);
            },
          );
        },
      ),
    );
  }
}

/// Bottom sheet that hosts a form; returns when closed.
Future<T?> showForm<T>(BuildContext context, {required String title, required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(color: context.fg)),
            const SizedBox(height: 16),
            builder(ctx),
          ],
        ),
      ),
    ),
  );
}

Widget field(TextEditingController c, String label,
        {TextInputType? type, bool obscure = false, int maxLines = 1, String? hint}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
        obscureText: obscure,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
