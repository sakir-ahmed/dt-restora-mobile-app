import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_screen.dart';
import 'home_screen.dart';

/// Left navigation drawer mirroring the web admin's sidebar: module groups
/// with colour-coded icons, then account and app actions at the bottom.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final visible = modules
        .where((m) => m.role != null ? app.hasRole(m.role!) : m.permission == null || app.can(m.permission!))
        .toList();
    final branch = (app.bootstrap?['branch'] as Map?)?['name'] as String?;
    final waiting = app.pendingCount + app.conflictCount;

    return Drawer(
      child: SafeArea(
        right: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Brand header, like the admin sidebar's top strip.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF0A1428), brandColors(app.brandKey).$1],
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const BrandLogo(size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(app.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(app.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Brand.soft, fontSize: 11.5)),
                  ]),
                ),
              ]),
              if (branch != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.storefront, size: 12, color: Colors.white70),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(branch,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              children: [
                for (final group in visible.map((m) => m.group).toSet()) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 12, bottom: 2),
                    child: Text(
                      group.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: context.muted,
                      ),
                    ),
                  ),
                  for (final m in visible.where((m) => m.group == group))
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: Icon(m.icon, size: 20, color: groupColor(context, group)),
                      title: Text(m.title, style: const TextStyle(fontSize: 13.5)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: m.builder));
                      },
                    ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: Column(children: [
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.sync_outlined, size: 20),
                title: const Text('Sync and outbox', style: TextStyle(fontSize: 13.5)),
                trailing: waiting > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: app.conflictCount > 0 ? Brand.danger : Brand.warning,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$waiting',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
                      )
                    : null,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen())),
              ),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.settings_outlined, size: 20),
                title: const Text('Settings', style: TextStyle(fontSize: 13.5)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
              SwitchListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                secondary: Icon(context.isDark ? Icons.dark_mode : Icons.light_mode, size: 20),
                title: const Text('Dark mode', style: TextStyle(fontSize: 13.5)),
                value: context.isDark,
                onChanged: (_) => app.setThemeMode(context.isDark ? ThemeMode.light : ThemeMode.dark),
              ),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.logout, size: 20, color: Brand.danger),
                title: const Text('Log out', style: TextStyle(fontSize: 13.5, color: Brand.danger)),
                onTap: () => _logout(context),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final app = AppScope.read(context);
    if (await confirm(context, 'Log out?',
        body: 'You will need your password to sign in to ${app.appName} again.', action: 'Log out')) {
      await app.logout();
      if (context.mounted) {
        Navigator.pop(context);
      }
    }
  }
}
