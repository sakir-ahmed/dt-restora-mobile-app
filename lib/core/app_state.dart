import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'local_db.dart';

/// A GET result that may come from the device cache when offline.
class Cached<T> {
  Cached(this.data, {this.fromCache = false, this.savedAt, this.meta});

  final T data;
  final bool fromCache;
  final DateTime? savedAt;
  final Map<String, dynamic>? meta;
}

/// Demo accounts seeded by DemoStaffSeeder (shared password).
class DemoAccount {
  const DemoAccount(this.username, this.role, this.hint);

  final String username;
  final String role;
  final String hint;
}

const demoPassword = 'Password123';

const demoAccounts = [
  DemoAccount('owner', 'Owner', 'All branches, full access'),
  DemoAccount('manager', 'Branch manager', 'Gulshan: ops, stock, staff'),
  DemoAccount('cashier', 'Cashier', 'Gulshan: POS and shifts'),
  DemoAccount('waiter', 'Waiter', 'Gulshan: take orders'),
  DemoAccount('kitchen', 'Kitchen manager', 'Kitchen display and stock'),
  DemoAccount('accountant', 'Accountant', 'Ledger, vouchers, reports'),
  DemoAccount('rider', 'Rider', 'Deliveries and cash to hand over'),
  DemoAccount('manager.dhanmondi', 'Manager (Dhanmondi)', 'Second branch'),
  DemoAccount('cashier.uttara', 'Cashier (Uttara)', 'Third branch'),
];

String newClientId() {
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  final rnd = Random.secure();
  var time = DateTime.now().millisecondsSinceEpoch;
  final timePart = StringBuffer();
  for (var i = 0; i < 10; i++) {
    timePart.write(alphabet[time % 32]);
    time ~/= 32;
  }
  final rand = List.generate(16, (_) => alphabet[rnd.nextInt(32)]).join();
  return '${timePart.toString().split('').reversed.join()}$rand';
}

/// Lets background sync show a message from anywhere in the app.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

class AppState extends ChangeNotifier {
  AppState({required this.api, required this.db});

  final ApiClient api;
  final LocalDb db;

  Map<String, dynamic>? user;
  Map<String, dynamic>? bootstrap;
  int branchId = 1;
  bool online = true;
  bool syncing = false;
  int pendingCount = 0;
  int conflictCount = 0;
  DateTime? lastSyncAt;
  String locale = 'en';

  /// One-time app configuration (setup screen). Falls back to defaults
  /// until the device has been set up.
  String appName = 'DT Restora';
  bool configured = false;

  /// Selected brand palette key (see theme.dart); blue is the default.
  String brandKey = 'blue';

  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  StreamSubscription<void>? _unauthSub;
  Timer? _timer;

  bool get isLoggedIn => user != null;
  String get userName => (user?['name'] as String?) ?? '';

  List<String> get roles =>
      ((user?['roles'] as List?) ?? const []).cast<String>();
  Set<String> get permissions =>
      ((user?['permissions'] as List?) ?? const []).cast<String>().toSet();

  bool can(String permission) => permissions.contains(permission);
  bool hasRole(String role) => roles.contains(role);
  bool get isRider => hasRole('rider');

  /// Owners and accountants are not tied to one branch.
  bool get isMultiBranch => user?['branch_id'] == null;

  ThemeMode themeMode = ThemeMode.system;

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode');
    themeMode =
        ThemeMode.values.where((m) => m.name == saved).firstOrNull ??
        ThemeMode.system;
    appName = prefs.getString('app_name') ?? 'DT Restora';
    configured = prefs.getBool('app_configured') ?? false;
    brandKey = prefs.getString('brand_key') ?? 'blue';
    locale = prefs.getString('menu_locale') ?? 'en';
    await api.restore();
    api.language = locale;
    _unauthSub = api.onUnauthorized.listen((_) => logout(silent: true));
    _connectivity = Connectivity().onConnectivityChanged.listen((results) {
      final nowOnline = results.any((r) => r != ConnectivityResult.none);
      if (nowOnline != online) {
        online = nowOnline;
        notifyListeners();
        if (nowOnline) {
          syncNow();
        }
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => syncNow());

    if (api.hasToken) {
      final cachedMe = await db.getCache('me');
      if (cachedMe != null) {
        user = Map<String, dynamic>.from(cachedMe.data as Map);
        branchId = (user?['branch_id'] as int?) ?? await _savedBranch() ?? 1;
        bootstrap =
            (await db.getCache('bootstrap:$branchId'))?.data
                as Map<String, dynamic>?;
      }
      await refreshPending();
      unawaited(_refreshProfileAndSync());
    }
  }

  Future<int?> _savedBranch() async =>
      (await db.getCache('branch_choice'))?.data as int?;

  Future<void> _refreshProfileAndSync() async {
    try {
      final me = await api.get('/auth/me');
      user = Map<String, dynamic>.from(me as Map);
      await db.putCache('me', user);
      notifyListeners();
      await syncNow();
    } on ApiException {
      // Offline or expired; unauthorized handler deals with 401.
    }
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    _unauthSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> login(String login, String password) async {
    final data = await api.post(
      '/auth/login',
      body: {'login': login.trim(), 'password': password},
    ) as Map<String, dynamic>;
    await api.saveToken(data['token'] as String);
    user = Map<String, dynamic>.from(data['user'] as Map);
    await db.putCache('me', user);
    branchId = (user?['branch_id'] as int?) ?? 1;
    await db.putCache('branch_choice', branchId);
    notifyListeners();
    await loadBootstrap();
    unawaited(syncNow());
  }

  Future<void> logout({bool silent = false}) async {
    if (!silent) {
      try {
        await api.post('/auth/logout');
      } on ApiException {
        // Token is dropped locally either way.
      }
    }
    await api.clearToken();
    await db.wipe();
    user = null;
    bootstrap = null;
    pendingCount = 0;
    conflictCount = 0;
    notifyListeners();
  }

  Future<void> setLocale(String code) async {
    locale = code;
    api.language = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('menu_locale', code);
  }

  /// Saves the one-time app configuration from the setup screen. The setup
  /// screen is never shown again until app storage is cleared.
  Future<void> completeSetup({
    required String name,
    required String baseUrl,
  }) async {
    await api.setBaseUrl(baseUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_configured', true);
    await prefs.setString('app_name', name);
    appName = name;
    configured = true;
    notifyListeners();
  }

  /// Renames the app from Settings; shown on the splash screen, app bar,
  /// drawer and footer.
  Future<void> setAppName(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) {
      return;
    }
    appName = clean;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_name', clean);
  }

  /// Switches the brand palette; applied to the theme at once.
  Future<void> setBrand(String key) async {
    brandKey = key;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('brand_key', key);
  }

  Future<void> switchBranch(int id) async {
    branchId = id;
    await db.putCache('branch_choice', id);
    bootstrap =
        (await db.getCache('bootstrap:$id'))?.data as Map<String, dynamic>?;
    notifyListeners();
    await loadBootstrap();
  }

  /// Menu, tables, VAT settings for the active branch, for offline POS.
  Future<void> loadBootstrap() async {
    try {
      final data = await api.get(
        '/sync/bootstrap',
        query: {'branch_id': branchId},
      ) as Map<String, dynamic>;
      if (isMultiBranch && (data['branch'] as Map?)?['id'] != branchId) {
        // The endpoint follows the user's branch; keep what the server chose.
        branchId = ((data['branch'] as Map)['id'] as num).toInt();
      }
      bootstrap = data;
      await db.putCache('bootstrap:$branchId', data);
      notifyListeners();
    } on ApiException catch (e) {
      if (!e.isNetwork) {
        debugPrint('bootstrap failed: $e');
      }
    }
  }

  int get dataVersion => (bootstrap?['data_version'] as num?)?.toInt() ?? 0;

  // ---------------------------------------------------------------- reads

  static String _cacheKey(String path, Map<String, dynamic>? query) =>
      'GET:$path?${(query ?? {}).entries.map((e) => '${e.key}=${e.value}').join('&')}';

  /// Last saved response for a GET, without touching the network.
  Future<Cached<dynamic>?> peekCache(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final hit = await db.getCache(_cacheKey(path, query));
    if (hit == null) {
      return null;
    }
    final body = hit.data as Map<String, dynamic>;
    return Cached(
      body['data'],
      fromCache: true,
      savedAt: hit.savedAt,
      meta: body['meta'] as Map<String, dynamic>?,
    );
  }

  /// GET with a device-cache fallback so every list works offline.
  Future<Cached<dynamic>> cachedGet(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final key = _cacheKey(path, query);
    try {
      final result = await api.send('GET', path, query: query);
      await db.putCache(key, {'data': result.data, 'meta': result.meta});
      if (!online) {
        online = true;
        notifyListeners();
      }
      return Cached(result.data, meta: result.meta);
    } on ApiException catch (e) {
      if (!e.isNetwork) {
        rethrow;
      }
      if (online) {
        online = false;
        notifyListeners();
      }
      final hit = await db.getCache(key);
      if (hit == null) {
        throw ApiException(
          'You are offline and this screen has not been opened before.',
          code: 'NETWORK',
        );
      }
      final body = hit.data as Map<String, dynamic>;
      return Cached(
        body['data'],
        fromCache: true,
        savedAt: hit.savedAt,
        meta: body['meta'] as Map<String, dynamic>?,
      );
    }
  }

  // ---------------------------------------------------------------- writes

  /// Queue an offline-capable write. It is sent at once when online and
  /// kept on the device otherwise. Returns true when the server took it now.
  Future<bool> queue(
    String type,
    Map<String, dynamic> payload, {
    String? label,
    String? clientId,
  }) async {
    final item = OutboxItem(
      clientId: clientId ?? newClientId(),
      type: type,
      payload: payload,
      createdAtDevice: DateTime.now().toUtc().toIso8601String(),
      dataVersion: dataVersion,
      status: OutboxStatus.pending,
      label: label,
    );
    await db.enqueue(item);
    await refreshPending();
    await syncNow();
    final done = (await db.outbox())
        .where((o) => o.clientId == item.clientId)
        .toList();
    return done.isEmpty || done.first.status != OutboxStatus.pending;
  }

  /// A sale made offline is on the server now: mark its snapshot as synced
  /// and, when the server had to issue another invoice number, say so.
  Future<void> _afterSynced(Map<String, dynamic> result) async {
    final clientId = result['id'] as String;
    final invoice = result['invoice_no'] as String?;
    await db.markLocalOrderSynced(clientId, invoiceNo: invoice);
    if (result['invoice_changed'] == true && invoice != null) {
      rootMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            'An offline invoice was renumbered to $invoice. Reprint the receipt if the customer needs it.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> refreshPending() async {
    final all = await db.outbox();
    pendingCount = all.where((o) => o.status == OutboxStatus.pending).length;
    conflictCount = all.where((o) => o.status == OutboxStatus.conflict).length;
    notifyListeners();
  }

  /// Push pending items in order, then refresh reference data.
  Future<void> syncNow() async {
    if (syncing || !isLoggedIn) {
      return;
    }
    syncing = true;
    notifyListeners();
    try {
      final pending = await db.outbox(status: OutboxStatus.pending);
      for (var i = 0; i < pending.length; i += 50) {
        final chunk = pending.skip(i).take(50).toList();
        final data = await api.post(
          '/sync/push',
          body: {'items': chunk.map((c) => c.toPushJson()).toList()},
        ) as Map<String, dynamic>;
        for (final r
            in (data['results'] as List).cast<Map<String, dynamic>>()) {
          final status = switch (r['status']) {
            'accepted' => OutboxStatus.accepted,
            'duplicate' => OutboxStatus.duplicate,
            _ => OutboxStatus.conflict,
          };
          await db.markOutbox(
            r['id'] as String,
            status,
            reason: r['reason'] as String?,
          );
          if (status != OutboxStatus.conflict) {
            await _afterSynced(r);
          }
        }
      }
      await db.purgeDone();
      await db.purgeOldSyncedOrders();
      lastSyncAt = DateTime.now();
      if (!online) {
        online = true;
      }
      await loadBootstrap();
    } on ApiException catch (e) {
      if (e.isNetwork && online) {
        online = false;
      }
    } finally {
      syncing = false;
      await refreshPending();
    }
  }
}
