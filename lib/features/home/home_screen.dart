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

class Module {
  const Module(this.title, this.icon, this.permission, this.builder, {this.role, this.group = 'Sell'});

  final String title;
  final String group;
  final IconData icon;

  /// Required permission, or null when everyone may open it.
  final String? permission;
  final String? role;
  final WidgetBuilder builder;
}

final modules = <Module>[
  Module('POS', Icons.point_of_sale, 'pos.access', (_) => const PosScreen(), group: 'Sell'),
  Module('Orders', Icons.receipt_long, 'orders.view', (_) => const OrdersScreen(), group: 'Sell'),
  Module('Kitchen', Icons.soup_kitchen, 'kds.access', (_) => const KitchenScreen(), group: 'Sell'),
  Module('Cash shift', Icons.savings, 'shifts.manage', (_) => const ShiftScreen(), group: 'Sell'),
  Module('Delivery', Icons.delivery_dining, 'delivery.dispatch', (_) => const DispatchScreen(), group: 'Delivery'),
  Module('My deliveries', Icons.two_wheeler, null, (_) => const RiderScreen(), role: 'rider', group: 'Delivery'),
  Module('Stock', Icons.inventory_2, 'inventory.view', (_) => const StockScreen(), group: 'Inventory'),
  Module('Wastage', Icons.delete_sweep, 'wastage.log', (_) => const WastageScreen(), group: 'Inventory'),
  Module('Purchases', Icons.shopping_cart, 'purchases.manage', (_) => const PurchasesScreen(), group: 'Inventory'),
  Module('Stock count', Icons.fact_check, 'inventory.manage', (_) => const StockCountScreen(), group: 'Inventory'),
  Module('Transfers', Icons.swap_horiz, 'transfers.manage', (_) => const TransfersScreen(), group: 'Inventory'),
  Module('Recipes', Icons.menu_book, 'recipes.manage', (_) => const RecipesScreen(), group: 'Inventory'),
  Module('Menu', Icons.restaurant_menu, 'menu.view', (_) => const MenuViewScreen(), group: 'Menu and tables'),
  Module('Tables', Icons.table_restaurant, 'tables.view', (_) => const TablesScreen(), group: 'Menu and tables'),
  Module('Staff', Icons.badge, 'staff.view', (_) => const StaffScreen(), group: 'People'),
  Module('Customers', Icons.people, 'customers.view', (_) => const CustomersScreen(), group: 'People'),
  Module('Coupons', Icons.local_offer, 'coupons.manage', (_) => const CouponsScreen(), group: 'People'),
  Module('Aggregators', Icons.hub, 'aggregators.manage', (_) => const AggregatorsScreen(), group: 'Business'),
  Module('Accounting', Icons.account_balance, 'accounting.view', (_) => const AccountingScreen(), group: 'Business'),
  Module('Reports', Icons.bar_chart, 'reports.view', (_) => const ReportsScreen(), group: 'Business'),
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
      appBar: AppBar(
        title: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/brand/logo-512.png', width: 34, height: 34),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DT Restora', style: TextStyle(fontSize: 17)),
              if (branch != null)
                Text(branch, style: const TextStyle(fontSize: 12, color: Brand.accent), overflow: TextOverflow.ellipsis),
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
              if (app.can('dashboard.view')) const DashboardSummary(),
              for (final group in visible.map((m) => m.group).toSet()) ...[
                SectionTitle(group),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.05,
                  children: [
                    for (final m in visible.where((m) => m.group == group))
                      Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: m.builder)),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: context.brand.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(m.icon, size: 24, color: context.brand),
                              ),
                              const SizedBox(height: 8),
                              Text(m.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ),
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
