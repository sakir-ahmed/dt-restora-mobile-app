import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/sounds.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _pickBranch(BuildContext context) async {
    final app = AppScope.read(context);
    final res = await app.cachedGet('/customer/branches');
    if (!context.mounted) {
      return;
    }
    final branches = asRows(res.data);
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final b in branches)
              ListTile(
                leading: Icon(
                  b['id'] == app.branchId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: context.brand,
                ),
                title: Text('${b['name']}'),
                onTap: () => Navigator.pop(ctx, (b['id'] as num).toInt()),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && chosen != app.branchId) {
      await app.switchBranch(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final branch =
        (app.bootstrap?['branch'] as Map?)?['name'] ?? 'Branch ${app.branchId}';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: context.pageBg,
                child: Icon(Icons.person, color: context.brand),
              ),
              title: Text(app.userName),
              subtitle: Text(
                '${app.user?['email'] ?? ''}\n${app.roles.map(titleCase).join(', ')}',
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.store),
                  title: const Text('Branch'),
                  subtitle: Text('$branch'),
                  trailing: app.isMultiBranch
                      ? const Icon(Icons.chevron_right)
                      : null,
                  onTap: app.isMultiBranch ? () => _pickBranch(context) : null,
                ),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('Menu language'),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('EN')),
                      ButtonSegment(value: 'bn', label: Text('BN')),
                    ],
                    selected: {app.locale},
                    onSelectionChanged: (s) => app.setLocale(s.first),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.brightness_6),
                  title: const Text('Appearance'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.settings_suggest),
                          label: Text('Auto'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {app.themeMode},
                      onSelectionChanged: (s) => app.setThemeMode(s.first),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Refresh menu and settings'),
                  onTap: () async {
                    await app.loadBootstrap();
                    if (context.mounted) {
                      snack(context, 'Reference data refreshed.');
                    }
                  },
                ),
                const _SoundsTile(),
                ListTile(
                  leading: const Icon(Icons.dns),
                  title: const Text('Server'),
                  subtitle: Text(app.api.baseUrl),
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Version'),
                  subtitle: Text(AppConfig.appVersion),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () async {
              final waiting = app.pendingCount + app.conflictCount;
              final ok = await confirm(
                context,
                'Sign out?',
                body: waiting > 0
                    ? '$waiting offline items have not been uploaded. Signing out will delete them.'
                    : null,
                action: 'Sign out',
              );
              if (ok) {
                await app.logout();
                if (context.mounted) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

/// Sound effects toggle and volume, like the branch sound settings on the
/// web app. Tapping the volume slider previews the payment chime.
class _SoundsTile extends StatefulWidget {
  const _SoundsTile();

  @override
  State<_SoundsTile> createState() => _SoundsTileState();
}

class _SoundsTileState extends State<_SoundsTile> {
  late bool _on = SoundFx.enabled;
  late double _volume = SoundFx.volume;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          secondary: Icon(
            _on ? Icons.volume_up : Icons.volume_off,
            color: context.brand,
          ),
          title: const Text('Sound effects'),
          subtitle: Text(
            _on ? 'Chimes for orders, payments and the kitchen' : 'Silent',
          ),
          value: _on,
          onChanged: (v) {
            setState(() => _on = v);
            SoundFx.setEnabled(v);
            if (v) {
              SoundFx.play('order_paid');
            }
          },
        ),
        if (_on)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.volume_down, size: 18, color: Brand.slate),
                Expanded(
                  child: Slider(
                    value: _volume,
                    onChanged: (v) {
                      setState(() => _volume = v);
                      SoundFx.setVolume(v);
                    },
                    onChangeEnd: (_) => SoundFx.play('order_paid'),
                  ),
                ),
                const Icon(Icons.volume_up, size: 18, color: Brand.slate),
              ],
            ),
          ),
      ],
    );
  }
}
