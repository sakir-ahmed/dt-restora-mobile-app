import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../accounting/accounting_screens.dart';
import '../aggregators/aggregator_screens.dart';
import '../customers/customer_screens.dart';
import '../dashboard/dashboard_screen.dart';
import '../delivery/delivery_screens.dart';
import '../inventory/inventory_screens.dart';
import '../orders/orders_screens.dart';
import '../pos/pos_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../shifts/shift_screen.dart';
import '../staff/staff_screens.dart';
import '../sync/sync_screen.dart';
import 'app_drawer.dart';

/// One screen per tile. Groups mirror the web admin's sidebar: Sales,
/// Inventory, People, Finance.
class Module {
  const Module(this.title, this.icon, this.permission, this.builder,
      {this.role, this.group = 'Sales', this.hero = false});

  final String title;
  final String group;
  final IconData icon;
  final bool hero;

  /// Required permission, or null when everyone may open it.
  final String? permission;
  final String? role;
  final WidgetBuilder builder;
}

final modules = <Module>[
  Module('Dashboard', Icons.dashboard_customize, 'dashboard.view', (_) => const DashboardScreen()),
  Module('POS', Icons.point_of_sale, 'pos.access', (_) => const PosScreen(), hero: true),
  Module('Orders', Icons.receipt_long, 'orders.view', (_) => const OrdersScreen()),
  Module('Kitchen', Icons.soup_kitchen, 'kds.access', (_) => const KitchenScreen()),
  Module('Cash shift', Icons.savings, 'shifts.manage', (_) => const ShiftScreen()),
  Module('Tables', Icons.table_restaurant, 'tables.view', (_) => const TablesScreen()),
  Module('Menu', Icons.restaurant_menu, 'menu.view', (_) => const MenuViewScreen(), group: 'Inventory'),
  Module('Stock', Icons.inventory_2, 'inventory.view', (_) => const StockScreen(), group: 'Inventory'),
  Module('Wastage', Icons.delete_sweep, 'wastage.log', (_) => const WastageScreen(), group: 'Inventory'),
  Module('Purchases', Icons.shopping_cart, 'purchases.manage', (_) => const PurchasesScreen(), group: 'Inventory'),
  Module('Stock count', Icons.fact_check, 'inventory.manage', (_) => const StockCountScreen(), group: 'Inventory'),
  Module('Transfers', Icons.swap_horiz, 'transfers.manage', (_) => const TransfersScreen(), group: 'Inventory'),
  Module('Recipes', Icons.menu_book, 'recipes.manage', (_) => const RecipesScreen(), group: 'Inventory'),
  Module('Customers', Icons.people, 'customers.view', (_) => const CustomersScreen(), group: 'People'),
  Module('Coupons', Icons.local_offer, 'coupons.manage', (_) => const CouponsScreen(), group: 'People'),
  Module('Staff', Icons.badge, 'staff.view', (_) => const StaffScreen(), group: 'People'),
  Module('Delivery', Icons.delivery_dining, 'delivery.dispatch', (_) => const DispatchScreen(), group: 'People'),
  Module('My deliveries', Icons.two_wheeler, null, (_) => const RiderScreen(), role: 'rider', group: 'People'),
  Module('Accounting', Icons.account_balance, 'accounting.view', (_) => const AccountingScreen(), group: 'Finance'),
  Module('Reports', Icons.bar_chart, 'reports.view', (_) => const ReportsScreen(), group: 'Finance'),
  Module('Aggregators', Icons.hub, 'aggregators.manage', (_) => const AggregatorsScreen(), group: 'Finance'),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final visible = modules
        .where((m) => m.role != null ? app.hasRole(m.role!) : m.permission == null || app.can(m.permission!))
        .toList();
    final branch = (app.bootstrap?['branch'] as Map?)?['name'] as String?;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/brand/logo-512.png', width: 34, height: 34),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(app.appName, style: const TextStyle(fontSize: 17), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (branch != null)
                Text(branch, style: TextStyle(fontSize: 12, color: context.brand), overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        actions: [
          _SyncBadge(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen()))),
          IconButton(
            tooltip: 'Light or dark',
            icon: Icon(context.isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => app.setThemeMode(context.isDark ? ThemeMode.light : ThemeMode.dark),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      bottomNavigationBar: const AppFooter(),
      body: Column(children: [
        if (!app.online)
          Container(
            width: double.infinity,
            color: context.warnBg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'Offline. Orders, payments, shifts, wastage and counts are saved and sent when you reconnect.',
              style: TextStyle(fontSize: 12, color: context.warnFg),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Hello, ${app.userName.split(' ').first}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: context.fg, fontWeight: FontWeight.w700)),
              Text(app.roles.map(titleCase).join(', '), style: TextStyle(color: context.muted)),
              // The two most-used actions, each half the screen: POS on the
              // left, Orders on the right.
              if (app.can('pos.access') || app.can('orders.view'))
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 2),
                  child: Row(children: [
                    if (app.can('pos.access'))
                      Expanded(child: _HomeAction.primary(
                        icon: Icons.point_of_sale,
                        title: 'POS',
                        subtitle: 'New order',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen())),
                      )),
                    if (app.can('pos.access') && app.can('orders.view')) const SizedBox(width: 10),
                    if (app.can('orders.view'))
                      Expanded(child: _HomeAction.tonal(
                        icon: Icons.receipt_long,
                        title: 'Orders',
                        subtitle: 'Track and serve',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen())),
                      )),
                  ]),
                ),
              for (final group in visible.where((m) => !m.hero).map((m) => m.group).toSet()) ...[
                SectionTitle(group, color: groupColor(context, group)),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.05,
                  children: [
                    for (final m in visible.where((m) => m.group == group && !m.hero))
                      ModuleTile(module: m),
                  ],
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

/// Home grid tile with its group's accent colour.
class ModuleTile extends StatelessWidget {
  const ModuleTile({super.key, required this.module});

  final Module module;

  @override
  Widget build(BuildContext context) {
    final color = groupColor(context, module.group);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: module.builder)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(module.icon, size: 24, color: color),
            ),
            const SizedBox(height: 8),
            Text(module.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Large half-width action button for the top of the home page. Primary is
/// the filled brand gradient; tonal is the quiet card style.
class _HomeAction extends StatelessWidget {
  const _HomeAction.primary(
      {required this.icon, required this.title, required this.subtitle, required this.onTap})
      : primary = true;

  const _HomeAction.tonal({required this.icon, required this.title, required this.subtitle, required this.onTap})
      : primary = false;

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final height = 72.0;
    if (primary) {
      final (c1, c2, _) = brandColors(AppScope.of(context).brandKey);
      return Material(
        color: Colors.transparent,
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c1, c2]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: c1.withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.brand.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: context.brand, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: context.muted)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final waiting = app.pendingCount + app.conflictCount;
    final icon = app.syncing
        ? Icons.sync
        : app.online
            ? (waiting == 0 ? Icons.cloud_done : Icons.cloud_upload)
            : Icons.cloud_off;
    return Stack(alignment: Alignment.center, children: [
      IconButton(tooltip: 'Sync', onPressed: onTap, icon: Icon(icon)),
      if (waiting > 0)
        Positioned(
          right: 6,
          top: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: app.conflictCount > 0 ? Brand.danger : Brand.warning,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$waiting', style: const TextStyle(fontSize: 10, color: Colors.white)),
          ),
        ),
    ]);
  }
}
